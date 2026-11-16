require "test_helper"

class Insight::Generators::FixedCommitmentsRatioGeneratorTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 11, 16)
    @family = families(:dylan_family)
    # `depository` is shared with every member; `connected` is private to the admin.
    @shared = accounts(:depository)
    @private = accounts(:connected)

    Entry.where(account_id: @family.accounts.select(:id), entryable_type: "Transaction").delete_all
    @family.recurring_transactions.destroy_all
  end

  test "flags commitments rising exactly the threshold against six months ago" do
    monthly_income(4_000)
    commitment("Rent", 1_200, since: 2.years.ago)
    commitment("Gym", 200, since: 2.months.ago)

    insight = generate.sole

    assert_equal "fixed_commitments_ratio", insight.insight_type
    assert_equal "fixed_commitments_ratio:2026-11", insight.dedup_key
    assert_equal "medium", insight.priority
    assert_equal({ current_ratio: 35.0, previous_ratio: 30.0 }, insight.metadata)
    assert_equal "35.0", insight.facts[:current_ratio]
    assert_equal "30.0", insight.facts[:previous_ratio]
    assert_equal "5.0", insight.facts[:change_pp]
    assert_includes insight.facts[:explanation], "Gym"
    assert_not_includes insight.facts[:explanation], "Rent"
  end

  test "stays quiet just under the rise threshold" do
    monthly_income(4_000)
    commitment("Rent", 1_200, since: 2.years.ago)
    commitment("Gym", 199.6, since: 2.months.ago)

    assert_empty generate
  end

  test "flags crossing half of income even when the rise is small" do
    monthly_income(4_000)
    commitment("Rent", 1_900, since: 2.years.ago)
    commitment("Phone", 100, since: 2.months.ago)

    insight = generate.sole

    assert_equal "high", insight.priority
    assert_equal I18n.t("insights.titles.fixed_commitments_ratio.over_half"), insight.title
    assert_equal 50.0, insight.metadata[:current_ratio]
  end

  test "stays quiet just under half of income" do
    monthly_income(4_000)
    commitment("Rent", 1_900, since: 2.years.ago)
    commitment("Phone", 96, since: 2.months.ago)

    assert_empty generate
  end

  test "stays quiet when commitments were already above half six months ago" do
    monthly_income(4_000)
    commitment("Rent", 2_400, since: 2.years.ago)
    commitment("Phone", 100, since: 2.months.ago)

    assert_empty generate
  end

  test "a price rise counts as a contributor with the amount it added" do
    monthly_income(4_000)
    rent = commitment("Rent", 1_400, since: 2.years.ago)
    rent.recurring_price_changes.create!(effective_on: 3.months.ago.to_date, previous_amount: 1_200,
                                         new_amount: 1_400, currency: "USD", source: "user")

    insight = generate.sole

    assert_equal({ current_ratio: 35.0, previous_ratio: 30.0 }, insight.metadata)
    assert_includes insight.facts[:explanation], "Rent"
    assert_includes insight.facts[:explanation], "$200.00"
  end

  test "a series that ended since counts six months ago, so a swap is not a rise" do
    monthly_income(4_000)
    commitment("Rent", 1_200, since: 2.years.ago)
    commitment("Old gym", 200, since: 2.years.ago, status: "ended", cancelled_on: 2.months.ago.to_date,
               last_occurrence_date: 2.months.ago.to_date)
    commitment("New gym", 200, since: 2.months.ago)

    assert_empty generate
  end

  test "explains a rise caused by lower income" do
    monthly_income(3_000, months: 1..6)
    monthly_income(4_000, months: 7..12)
    commitment("Rent", 1_200, since: 2.years.ago)

    insight = generate.sole

    assert_equal({ current_ratio: 40.0, previous_ratio: 30.0 }, insight.metadata)
    assert_includes insight.facts[:explanation], "$3,000.00"
    assert_includes insight.facts[:explanation], "$4,000.00"
  end

  test "uses the median income so a bonus month does not hide the rise" do
    monthly_income(4_000)
    income_in(2, 12_000)
    commitment("Rent", 1_200, since: 2.years.ago)
    commitment("Gym", 200, since: 2.months.ago)

    assert_equal 35.0, generate.sole.metadata[:current_ratio]
  end

  test "counts recurring payments into a loan but not into other accounts" do
    monthly_income(4_000)
    commitment("Rent", 1_200, since: 2.years.ago)
    shared_loan, shared_asset = accounts(:loan), accounts(:other_asset)
    [ shared_loan, shared_asset ].each do |account|
      AccountShare.create!(account: account, user: users(:family_member), permission: "read_only")
    end
    commitment("Mortgage payment", 400, since: 2.months.ago, destination_account: shared_loan)
    commitment("Savings sweep", 400, since: 2.months.ago, destination_account: shared_asset)

    assert_equal({ current_ratio: 40.0, previous_ratio: 30.0 }, generate.sole.metadata)
  end

  test "leaves out series on an account that is private to one member" do
    monthly_income(4_000)
    commitment("Rent", 1_200, since: 2.years.ago)
    commitment("Private club", 400, since: 2.months.ago, account: @private)

    assert_empty generate
  end

  test "returns nothing without income six months ago to compare with" do
    monthly_income(4_000, months: 1..6)
    commitment("Rent", 1_200, since: 2.months.ago)

    assert_empty generate
  end

  test "returns nothing without recurring commitments" do
    monthly_income(4_000)

    assert_empty generate
  end

  test "returns nothing when recurring transactions are disabled" do
    monthly_income(4_000)
    commitment("Rent", 1_200, since: 2.years.ago)
    commitment("Gym", 400, since: 2.months.ago)
    @family.update!(recurring_transactions_disabled: true)

    assert_empty generate
  end

  test "writes the body in English and Spanish" do
    monthly_income(4_000)
    commitment("Rent", 1_200, since: 2.years.ago)
    commitment("Gym", 200, since: 2.months.ago)

    %i[en es].each do |locale|
      I18n.with_locale(locale) do
        insight = generate.sole
        body = Insight::BodyWriter.new.write(insight)

        assert_includes body, "Gym"
        assert_includes body, { en: "35.0%", es: "35,0%" }.fetch(locale)
        assert_no_match(/translation missing/i, body)
        assert_no_match(/translation missing/i, insight.title)
      end
    end
  end

  private
    def generate
      Insight::Generators::FixedCommitmentsRatioGenerator.new(@family).generate
    end

    # Income on the 15th of each of the given complete months back from today.
    def monthly_income(amount, months: 1..12)
      months.each { |offset| income_in(offset, amount) }
    end

    def income_in(months_ago, amount)
      create_transaction(account: @shared, amount: -amount, name: "Salary",
                         date: (Date.current.beginning_of_month << months_ago).change(day: 15))
    end

    def commitment(name, amount, since:, account: @shared, **attributes)
      series = @family.recurring_transactions.create!(
        name: name, account: account, amount: amount, currency: "USD", expected_day_of_month: 1,
        last_occurrence_date: Date.current.beginning_of_month, next_expected_date: Date.current.next_month.beginning_of_month,
        status: "active", manual: true, **attributes
      )
      series.update_columns(created_at: since)
      series.recurring_occurrences.delete_all
      series
    end
end
