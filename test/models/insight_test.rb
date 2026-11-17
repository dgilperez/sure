require "test_helper"

class InsightTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @insight = insights(:spending_anomaly_dining)
  end

  test "mark_read! transitions active insight and stamps read_at" do
    assert @insight.active?

    @insight.mark_read!

    assert @insight.reload.read?
    assert @insight.read_at.present?
  end

  test "mark_read! does not touch acknowledged insights" do
    @insight.acknowledge!

    @insight.mark_read!

    assert @insight.reload.acknowledged?
    assert_nil @insight.read_at
  end

  test "acknowledge! removes insight from visible scope" do
    assert_includes Insight.visible, @insight

    @insight.acknowledge!

    assert_not_includes Insight.visible, @insight
    assert @insight.dismissed_at.present?
  end

  test "unacknowledge! restores an acknowledged insight as read, not new" do
    @insight.acknowledge!

    @insight.unacknowledge!

    assert @insight.reload.read?
    assert_nil @insight.dismissed_at
    assert @insight.read_at.present?
    assert_includes Insight.visible, @insight
  end

  # A stale/replayed undo (e.g. an old toast link clicked after the insight
  # has since expired or resurrected) must not force a non-acknowledged
  # insight back to :read — that would wrongly pull an :expired insight back
  # into view.
  test "unacknowledge! is a no-op on an insight that isn't acknowledged" do
    @insight.update!(status: :expired)

    @insight.unacknowledge!

    assert @insight.reload.expired?
  end

  test "duplicate dedup_key within a family is rejected" do
    assert_raises ActiveRecord::RecordInvalid do
      @insight.family.insights.create!(
        insight_type: @insight.insight_type,
        priority: "medium",
        title: "Duplicate",
        body: "Duplicate body",
        dedup_key: @insight.dedup_key
      )
    end
  end

  test "same dedup_key is allowed across families" do
    other_family = families(:empty)

    assert_nothing_raised do
      other_family.insights.create!(
        insight_type: @insight.insight_type,
        priority: "medium",
        title: "Same key, other family",
        body: "Body",
        dedup_key: @insight.dedup_key
      )
    end
  end

  test "ordered puts high priority first, then most recent" do
    high = insights(:cash_flow_warning)

    assert_equal high, Insight.ordered.first
  end

  test "insight_type must be a known type" do
    insight = Insight.new(
      family: families(:empty),
      insight_type: "bogus",
      title: "t",
      body: "b",
      dedup_key: "bogus:key"
    )

    assert_not insight.valid?
    assert insight.errors[:insight_type].any?
  end

  test "visible hides an insight about an account a member cannot see" do
    family = families(:dylan_family)
    shared = idle_cash_insight(family, accounts(:depository))
    private_one = idle_cash_insight(family, accounts(:connected))
    gone = idle_cash_insight(family, Struct.new(:id).new(SecureRandom.uuid))

    visible = family.insights.visible

    assert_includes visible, shared
    assert_not_includes visible, private_one
    assert_not_includes visible, gone, "an insight about a deleted account is hidden too"
    assert_includes visible, @insight, "insights without an account are untouched"
    assert private_one.reload.active?, "hiding writes nothing; the row returns as it was"
  end

  test "revoking a share hides an insight about that account right away" do
    family = families(:dylan_family)
    insight = idle_cash_insight(family, accounts(:depository))

    accounts(:depository).unshare_with!(users(:family_member))

    assert_not_includes family.insights.visible, insight
  end

  test "a member joining without access hides an insight about the account" do
    family = families(:dylan_family)
    insight = idle_cash_insight(family, accounts(:depository))

    family.users.create!(email: "newcomer@example.com", password: "password123!A", first_name: "New", last_name: "Member", role: "member")

    assert_not_includes family.insights.visible, insight
  end

  test "an inactive member does not hide an insight" do
    family = families(:dylan_family)
    insight = idle_cash_insight(family, accounts(:connected))

    users(:family_member).update_columns(active: false)

    assert_includes family.insights.visible, insight
  end

  test "an insight about another family's account id is hidden" do
    family = families(:dylan_family)
    insight = idle_cash_insight(family, accounts(:connected))
    insight.update_columns(family_id: families(:empty).id)

    assert_not_includes families(:empty).insights.visible, insight
  end

  test "a malformed account id hides the insight instead of raising" do
    family = families(:dylan_family)
    insight = idle_cash_insight(family, Struct.new(:id).new("not-a-uuid"))

    assert_not_includes family.insights.visible.to_a, insight
  end

  test "an insight about an account pending deletion is hidden" do
    family = families(:dylan_family)
    insight = idle_cash_insight(family, accounts(:depository))

    accounts(:depository).update_columns(status: "pending_deletion")

    assert_not_includes family.insights.visible, insight
  end

  test "an insight about a recurring series follows the series' current account" do
    family = families(:dylan_family)
    series = recurring_transactions(:netflix_subscription)
    insight = subscription_audit_insight(family, series, account_id: series.account_id)
    assert_includes family.insights.visible, insight

    series.update_columns(account_id: accounts(:connected).id)
    assert_not_includes family.insights.visible, insight

    series.update_columns(account_id: nil)
    assert_includes family.insights.visible, insight
  end

  test "an insight about a deleted recurring series is hidden" do
    family = families(:dylan_family)
    series = recurring_transactions(:netflix_subscription)
    insight = subscription_audit_insight(family, series)

    series.destroy!

    assert_not_includes family.insights.visible, insight
  end

  # A total has no account to recheck on read, so a change in who can see
  # which account takes it off the feed at once, and one job rebuilds it from
  # the accounts everyone can still open.
  test "revoking a share expires the household's totals and schedules one rebuild" do
    family = families(:dylan_family)
    total = aggregate_insight(family)
    read_total = aggregate_insight(family, dedup_key: "savings_rate_change:read").tap(&:mark_read!)
    acknowledged = aggregate_insight(family, dedup_key: "savings_rate_change:old").tap(&:acknowledge!)
    per_account = idle_cash_insight(family, accounts(:depository))

    freeze_time do
      assert_enqueued_jobs 1, only: GenerateInsightsJob do
        accounts(:depository).unshare_with!(users(:family_member))
      end
      assert_enqueued_with job: GenerateInsightsJob, args: [ { family_id: family.id } ],
                           at: Insight::ACCESS_CHANGE_REBUILD_DELAY.from_now
    end

    assert total.reload.expired?
    assert read_total.reload.expired?
    assert_not total.metadata.key?("accounts_digest"), "the digest names an account set nobody holds any more"
    assert acknowledged.reload.acknowledged?, "what the user put away stays put away"
    assert per_account.reload.active?, "a row about one account is already hidden on read"
    assert_not_includes family.insights.visible, total
  end

  test "a member joining, leaving and rejoining schedules a single rebuild" do
    family = families(:dylan_family)
    total = aggregate_insight(family)

    assert_enqueued_jobs 1, only: GenerateInsightsJob do
      newcomer = family.users.create!(email: "newcomer@example.com", password: "password123!A",
                                      first_name: "New", last_name: "Member", role: "member")
      newcomer.update!(active: false)
      newcomer.update!(active: true)
    end

    assert total.reload.expired?
  end

  test "deactivating a member expires the household's totals" do
    family = families(:dylan_family)
    total = aggregate_insight(family)

    assert_enqueued_jobs 1, only: GenerateInsightsJob do
      users(:family_member).deactivate
    end

    assert total.reload.expired?
  end

  test "handing an account to another member expires the household's totals" do
    family = families(:dylan_family)
    total = aggregate_insight(family)

    assert_enqueued_jobs 1, only: GenerateInsightsJob do
      accounts(:connected).update!(owner: users(:family_member))
    end

    assert total.reload.expired?
  end

  test "sharing an account with a member expires the household's totals" do
    family = families(:dylan_family)
    total = aggregate_insight(family)

    assert_enqueued_jobs 1, only: GenerateInsightsJob do
      accounts(:connected).share_with!(users(:family_member))
    end

    assert total.reload.expired?
  end

  test "changes that leave access as it was expire nothing" do
    family = families(:dylan_family)
    total = aggregate_insight(family)

    assert_no_enqueued_jobs only: GenerateInsightsJob do
      accounts(:depository).update!(name: "Renamed checking")
      account_shares(:depository_shared_with_member).update!(permission: "read_only", include_in_finances: false)
      users(:family_member).update!(first_name: "Renamed")
    end

    assert total.reload.active?
  end

  test "an access change schedules nothing when no total is on the feed" do
    family = families(:dylan_family)
    aggregate_insight(family).acknowledge!

    assert_no_enqueued_jobs only: GenerateInsightsJob do
      accounts(:depository).unshare_with!(users(:family_member))
    end
  end

  test "an access change leaves other families' totals alone" do
    other = aggregate_insight(families(:empty))

    accounts(:depository).unshare_with!(users(:family_member))

    assert other.reload.active?
  end

  private
    def subscription_audit_insight(family, series, account_id: nil)
      family.insights.create!(
        insight_type: "subscription_audit", priority: "medium", status: "active", title: "Audit", body: "body",
        metadata: { "recurring_transaction_id" => series.id, "account_id" => account_id }.compact,
        dedup_key: "subscription_audit:#{series.id}", generated_at: Time.current
      )
    end

    def aggregate_insight(family, dedup_key: "savings_rate_change:current")
      family.insights.create!(
        insight_type: "savings_rate_change", priority: "medium", status: "active", title: "Savings", body: "body",
        metadata: { "current_rate" => 40.0, "accounts_digest" => "computed-from-the-old-set" },
        dedup_key: dedup_key, generated_at: Time.current
      )
    end

    def idle_cash_insight(family, account)
      family.insights.create!(
        insight_type: "idle_cash", priority: "low", status: "active", title: "Idle", body: "body",
        metadata: { "account_id" => account.id }, dedup_key: "idle_cash:#{account.id}",
        generated_at: Time.current
      )
    end
end
