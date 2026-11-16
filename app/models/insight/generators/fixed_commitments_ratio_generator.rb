# Tracks how much of a typical month's income is already spoken for by
# recurring commitments, and speaks up when that share rises RISE_THRESHOLD_PP
# points against six months ago, or crosses CEILING_PCT.
#
#   ratio = monthly equivalent of the recurring outflows in force
#           / median monthly income over the six complete months before
#
# The median, not the mean, so a month with extra pay (a bonus, a thirteenth
# payment) does not make commitments look smaller than they are.
#
# Outflows are expense series plus recurring payments into a loan. Payments
# into a credit card are left out: they repay spending that is already counted
# on the card, much of it not fixed at all.
#
# The figure six months ago is rebuilt from the series in force on that date,
# priced through their price history, so a series swapped for another of the
# same cost is not a rise. Cadence changes are not tracked: every series is
# normalised at its current cadence.
class Insight::Generators::FixedCommitmentsRatioGenerator < Insight::Generator
  produces "fixed_commitments_ratio"

  RISE_THRESHOLD_PP = 5
  CEILING_PCT = 50
  WINDOW_MONTHS = 6
  MAX_CONTRIBUTORS = 3

  def generate
    return [] if family.recurring_transactions_disabled?

    current_income = median_monthly_income(months_back: 0)
    previous_income = median_monthly_income(months_back: WINDOW_MONTHS)
    return [] unless current_income.positive? && previous_income.positive?

    current = monthly_commitments(series.select(&:active?))
    previous = monthly_commitments(series.select { |s| in_force_on?(s, reference_date) }, on: reference_date)
    return [] if current.empty?

    current_total = current.values.sum
    current_ratio = current_total / current_income * 100
    previous_ratio = previous.values.sum / previous_income * 100
    rise_pp = current_ratio - previous_ratio
    crossed_ceiling = previous_ratio < CEILING_PCT && current_ratio >= CEILING_PCT
    return [] unless rise_pp >= RISE_THRESHOLD_PP || crossed_ceiling

    variant = current_ratio >= CEILING_PCT ? "over_half" : "up"

    [
      build_insight(
        insight_type: "fixed_commitments_ratio",
        priority: variant == "over_half" ? "high" : "medium",
        title: I18n.t("insights.titles.fixed_commitments_ratio.#{variant}"),
        template_key: "fixed_commitments_ratio",
        facts: {
          current_ratio: decimal_fact(current_ratio),
          previous_ratio: decimal_fact(previous_ratio),
          change_pp: decimal_fact(rise_pp),
          commitments: format_money(current_total),
          income: format_money(current_income),
          explanation: explanation(current, previous, current_income, previous_income)
        },
        # Whole points: recurring amounts nudge with every averaged charge, and
        # a fraction of a point is not a new insight.
        metadata: {
          current_ratio: round(current_ratio, 0),
          previous_ratio: round(previous_ratio, 0)
        },
        period: income_window(months_back: 0),
        dedup_key: "fixed_commitments_ratio:#{month_token}"
      )
    ]
  end

  private
    def reference_date
      @reference_date ||= Date.current << WINDOW_MONTHS
    end

    # Every outflow series that was ever confirmed, on accounts every active
    # member can see: the body names them. Suggestions were never in force.
    def series
      @series ||= begin
        loans = family.accounts.where(accountable_type: "Loan").select(:id)
        outflows = RecurringTransaction.where(destination_account_id: nil)
                                       .or(RecurringTransaction.where(destination_account_id: loans))
        family.recurring_transactions
          .where.not(status: :suggested)
          .where("recurring_transactions.amount > 0")
          .merge(outflows)
          .within_accounts(family.accounts.accessible_by_all_active_members)
          .includes(:merchant, :recurrence_rules, :recurring_price_changes)
          .to_a
      end
    end

    # Started on or before `date` (its earliest occurrence, or its creation
    # for a series created ahead of its history), and not yet over by then.
    def in_force_on?(recurring, date)
      started_on = [ recurring.created_at.to_date, first_due_on[recurring.id] ].compact.min
      return false if started_on > date
      return true if recurring.active?

      (recurring.cancelled_on || recurring.last_occurrence_date) >= date
    end

    def first_due_on
      @first_due_on ||= family.recurring_occurrences
        .where(recurring_transaction_id: series.map(&:id))
        .group(:recurring_transaction_id)
        .minimum(:due_on)
    end

    # { series => monthly amount in the family currency }. A series with no
    # exchange rate is left out, as on the Bills page.
    def monthly_commitments(series_list, on: nil)
      series_list.each_with_object({}) do |recurring, amounts|
        amounts[recurring] = recurring.monthly_equivalent_amount(on: on).exchange_to(family.currency).amount
      rescue Money::ConversionError
        next
      end
    end

    # The complete months ending `months_back` months before last month.
    def income_window(months_back:)
      last_month = Period.last_month_for(family)
      Period.custom(start_date: last_month.start_date << (months_back + WINDOW_MONTHS - 1),
                    end_date: last_month.end_date << months_back)
    end

    def median_monthly_income(months_back:)
      window_start = income_window(months_back: months_back).start_date
      totals = (0...WINDOW_MONTHS).map do |offset|
        start_date = window_start >> offset
        period = Period.custom(start_date: start_date, end_date: (start_date >> 1) - 1)
        income_statement.income_totals(period: period).total.to_d
      end
      median(totals)
    end

    def median(values)
      sorted = values.sort
      middle = sorted.size / 2
      sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    end

    # The series that grew the most (new ones count in full), or, when none
    # grew, the drop in income that raised the share instead.
    def explanation(current, previous, current_income, previous_income)
      contributors = current.filter_map do |recurring, amount|
        added = amount - previous.fetch(recurring, 0)
        [ recurring, added ] if added.positive?
      end

      if contributors.empty?
        return I18n.t("insights.fixed_commitments_ratio.income_fell",
                      previous_income: format_money(previous_income), current_income: format_money(current_income))
      end

      names = contributors.max_by(MAX_CONTRIBUTORS) { |_, added| added }.map do |recurring, added|
        key = previous.key?(recurring) ? "raised" : "new"
        I18n.t("insights.fixed_commitments_ratio.contributor.#{key}",
               name: recurring.display_name, amount: format_money(added))
      end
      I18n.t("insights.fixed_commitments_ratio.contributors", list: names.to_sentence)
    end
end
