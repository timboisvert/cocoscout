# frozen_string_literal: true

class FinancialSummaryService
  PERIODS = {
    all_time: -> { nil },
    this_week: -> { Time.current.beginning_of_week..Time.current.end_of_week },
    last_week: -> { 1.week.ago.beginning_of_week..1.week.ago.end_of_week },
    this_month: -> { Time.current.beginning_of_month..Time.current.end_of_month },
    last_month: -> { 1.month.ago.beginning_of_month..1.month.ago.end_of_month },
    last_30_days: -> { 30.days.ago.beginning_of_day..Time.current.end_of_day },
    last_90_days: -> { 90.days.ago.beginning_of_day..Time.current.end_of_day },
    this_quarter: -> { Time.current.beginning_of_quarter..Time.current.end_of_quarter },
    last_quarter: -> { 3.months.ago.beginning_of_quarter..3.months.ago.end_of_quarter },
    this_year: -> { Time.current.beginning_of_year..Time.current.end_of_year },
    last_year: -> { 1.year.ago.beginning_of_year..1.year.ago.end_of_year }
  }.freeze

  PERIOD_LABELS = {
    all_time: "All Time",
    this_week: "This Week",
    last_week: "Last Week",
    this_month: "This Month",
    last_month: "Last Month",
    last_30_days: "Last 30 Days",
    last_90_days: "Last 90 Days",
    this_quarter: "This Quarter",
    last_quarter: "Last Quarter",
    this_year: "This Year",
    last_year: "Last Year"
  }.freeze

  # Quick access periods (shown as pills)
  QUICK_PERIODS = %i[this_month last_30_days this_year all_time].freeze

  # Accepts a single production or a collection of productions
  def initialize(productions)
    @productions = productions.respond_to?(:each) ? productions : [ productions ]
  end

  def self.quick_period_labels
    PERIOD_LABELS.slice(*QUICK_PERIODS)
  end

  def summary_for_period(period_key)
    range = PERIODS[period_key.to_sym]&.call
    calculate_summary(range)
  end

  # Every production's summary plus the combined total, from one pass.
  #
  # The pages that show a per-production grid used to build this by running the
  # whole service once per production — which meant re-querying, for each one,
  # shows the org-wide summary above the grid had already queried. Returns
  # { total: {...}, by_production: { id => {...} } }.
  def summaries_by_period(period_key)
    range = PERIODS[period_key.to_sym]&.call
    calculate_summary(range, by_production: true)
  end

  def self.summaries_by_production(productions, period_key)
    new(productions).summaries_by_period(period_key)
  end

  def all_period_summaries
    PERIODS.keys.index_with { |period| summary_for_period(period) }
  end

  # The all-zeros shape, for a production that has no shows in the period and so
  # never appears in a by_production map but still gets rendered a row.
  def self.empty_summary
    @empty_summary ||= new([]).summary_for_period(:all_time).freeze
  end

  def self.period_labels
    PERIOD_LABELS
  end

  private

  # One pass over the shows in range, accumulating into a combined bucket and —
  # when asked — a bucket per production. Every child table is fetched with a
  # single grouped query, so the cost is flat in the number of productions and
  # shows rather than a query or three per show.
  def calculate_summary(date_range, by_production: false)
    spine = show_spine(date_range)
    show_ids = spine.map(&:first)

    # expense_items is preloaded so the "does this row have any?" check is free.
    # It's the sum that would still hit the database on a loaded association,
    # and item_totals below answers that without asking.
    financials = ShowFinancials.where(show_id: show_ids).includes(:expense_items).index_by(&:show_id)
    item_totals, item_categories = expense_item_rollups(financials.values.map(&:id))
    allocations = ProductionExpenseAllocation.where(show_id: show_ids).group(:show_id).sum(:allocated_amount)
    payouts = ShowPayout.where(show_id: show_ids).group(:show_id).sum(:total_payout)

    total = new_bucket
    by_prod = Hash.new { |h, k| h[k] = new_bucket }
    show_ids_by_production = Hash.new { |h, k| h[k] = [] }

    spine.each do |show_id, production_id|
      show_ids_by_production[production_id] << show_id
      buckets = by_production ? [ total, by_prod[production_id] ] : [ total ]

      buckets.each do |bucket|
        bucket[:show_count] += 1
        # Payouts count for every show in scope, with or without financials.
        bucket[:total_payouts] += payouts[show_id].to_f
      end

      row = financials[show_id]
      next unless row&.has_data?

      buckets.each do |bucket|
        accumulate_financials(bucket, row,
                              items_total: item_totals[row.id],
                              categories: item_categories[row.id],
                              # A show missing from the grouped fetch genuinely
                              # has no allocations, so hand over a real zero —
                              # nil would send it back to the database to be
                              # told the same thing, one query per show.
                              allocated: allocations[show_id] || 0.0)
      end
    end

    contract_money = contract_money_by_production
    contract_money.each do |production_id, money|
      total[:contract_money_in] += money[:money_in]
      total[:contract_money_out] += money[:money_out]
      next unless by_production

      by_prod[production_id][:contract_money_in] += money[:money_in]
      by_prod[production_id][:contract_money_out] += money[:money_out]
    end

    total_summary = finalize(total, allocations, show_ids)
    return total_summary unless by_production

    {
      total: total_summary,
      by_production: by_prod.each_with_object({}) do |(production_id, bucket), out|
        out[production_id] = finalize(bucket, allocations, show_ids_by_production[production_id])
      end
    }
  end

  # (show_id, production_id) for every revenue show in range. Shows themselves
  # are never loaded — nothing here reads a Show attribute beyond these two.
  def show_spine(date_range)
    # Third-party productions are excluded: their revenue arrives through a
    # contract, not through show ticket sales.
    production_ids = @productions.reject(&:type_third_party?).map(&:id)
    scope = Show.where(production_id: production_ids)
                .where(event_type: EventTypes.revenue_event_types)
                .where(canceled: false) # A canceled show earned nothing — keep it out of the totals
                .where("date_and_time < ?", Time.current) # Only past shows
    scope = scope.where(date_and_time: date_range) if date_range
    scope.pluck(:id, :production_id)
  end

  # One grouped query answers both "what do this row's expense items total?" and
  # "how do they split by category?" — the two questions the old code asked
  # separately, per show.
  def expense_item_rollups(financials_ids)
    return [ {}, {} ] if financials_ids.empty?

    grouped = ExpenseItem.where(show_financials_id: financials_ids)
                         .group(:show_financials_id, :category).sum(:amount)
    # Plain hashes on purpose: a missing key has to read as nil, meaning "this
    # row has no expense items, use the legacy JSONB path". A default of 0.0
    # would look like "items totalling nothing" and silently zero those rows.
    totals = {}
    categories = {}
    grouped.each do |(financials_id, category), amount|
      totals[financials_id] = totals.fetch(financials_id, 0.0) + amount.to_f
      # presence, not SQL COALESCE: this also folds "" into "other", which is
      # what the row-at-a-time version did.
      key = category.presence || "other"
      row = (categories[financials_id] ||= Hash.new(0.0))
      row[key] += amount.to_f
    end
    [ totals, categories ]
  end

  def new_bucket
    { show_count: 0, shows_with_data: 0, gross_revenue: 0.0, show_expenses: 0.0,
      production_expenses: 0.0, total_payouts: 0.0, ticket_revenue: 0.0,
      flat_fee_revenue: 0.0, other_revenue: 0.0, contract_money_in: 0.0,
      contract_money_out: 0.0, expense_by_category: Hash.new(0.0) }
  end

  def accumulate_financials(bucket, row, items_total:, categories:, allocated:)
    bucket[:shows_with_data] += 1
    bucket[:gross_revenue] += row.total_revenue
    bucket[:show_expenses] += row.calculated_expenses(items_total: items_total)
    bucket[:production_expenses] += row.calculated_production_expenses(allocated: allocated)

    if row.ticket_sales?
      bucket[:ticket_revenue] += row.ticket_revenue
    else
      bucket[:flat_fee_revenue] += row.flat_fee.to_f
    end
    bucket[:other_revenue] += row.calculated_other_revenue

    if categories.present?
      categories.each { |category, amount| bucket[:expense_by_category][category] += amount }
    elsif row.normalized_expense_details.any?
      row.normalized_expense_details.each do |item|
        bucket[:expense_by_category][item["category"].presence || "other"] += item["amount"].to_f
      end
    elsif row.expenses.to_f > 0
      bucket[:expense_by_category]["other"] += row.expenses.to_f
    end
  end

  # Contract money folded in so third-party deals aren't siloed: their revenue
  # lands in money-in and their contractor payouts in money-out, like any show.
  # (Gross model — see Contract#money_summary.)
  def contract_money_by_production
    third_party = @productions.select(&:type_third_party?)
    ActiveRecord::Associations::Preloader.new(records: third_party, associations: :contracts).call

    with_contracts = third_party.filter_map { |p| [ p, p.contract ] if p.contract }
    Contract.preload_money_data(with_contracts.map(&:last))

    with_contracts.each_with_object({}) do |(production, contract), out|
      out[production.id] = contract.money_summary
    end
  end

  def finalize(bucket, allocations, scoped_show_ids)
    gross_revenue = bucket[:gross_revenue] + bucket[:contract_money_in]
    total_payouts = bucket[:total_payouts] + bucket[:contract_money_out]

    production_expenses = bucket[:production_expenses]
    # Production expenses are allocated to every show whether or not anyone has
    # entered financials, so a period with no entered data would otherwise report
    # none of them. Reads from the same grouped fetch rather than re-querying.
    if production_expenses.zero? && @productions.any?
      production_expenses = scoped_show_ids.sum { |id| allocations[id].to_f }
    end

    cost_of_shows = bucket[:show_expenses] + production_expenses + total_payouts
    gross_profit = gross_revenue - cost_of_shows
    gross_margin = gross_revenue > 0 ? (gross_profit / gross_revenue * 100).round(1) : 0
    # No operating expenses are tracked separately yet, so net income is gross profit.
    net_income = gross_profit
    shows_with_data = bucket[:shows_with_data]

    {
      show_count: bucket[:show_count],
      shows_with_data: shows_with_data,
      gross_revenue: gross_revenue,
      show_expenses: bucket[:show_expenses],
      production_expenses: production_expenses,
      total_payouts: total_payouts,
      cost_of_shows: cost_of_shows,
      gross_profit: gross_profit,
      gross_margin: gross_margin,
      net_income: net_income,
      average_revenue_per_show: shows_with_data > 0 ? (gross_revenue / shows_with_data).round(2) : 0,
      # Breakdowns
      ticket_revenue: bucket[:ticket_revenue],
      flat_fee_revenue: bucket[:flat_fee_revenue],
      other_revenue: bucket[:other_revenue],
      # Contract revenue is folded into gross_revenue above (gross model); this
      # key points at that same money-in figure.
      contract_revenue: bucket[:contract_money_in],
      expense_by_category: bucket[:expense_by_category],
      # Legacy keys for backward compatibility during transition
      total_revenue: gross_revenue,
      total_expenses: bucket[:show_expenses],
      net_profit: gross_profit,
      profit_margin: gross_margin,
      retained: net_income
    }
  end
end
