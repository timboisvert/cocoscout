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

  def all_period_summaries
    PERIODS.keys.each_with_object({}) do |period, hash|
      hash[period] = summary_for_period(period)
    end
  end

  def self.period_labels
    PERIOD_LABELS
  end

  private

  def calculate_summary(date_range)
    # Only include revenue events (shows, classes, workshops) - not rehearsals/meetings
    revenue_event_types = EventTypes.revenue_event_types

    # Build scope across all productions
    production_ids = @productions.map(&:id)
    scope = Show.where(production_id: production_ids)
                .where(event_type: revenue_event_types)
                .where("date_and_time < ?", Time.current) # Only past shows

    if date_range
      scope = scope.where(date_and_time: date_range)
    end

    # Get shows with financials
    shows_with_financials = scope.includes(:show_financials, :show_payout)

    # Calculate totals
    gross_revenue = 0.0
    show_expenses = 0.0
    production_expenses = 0.0
    shows_with_data = 0
    expense_by_category = Hash.new(0.0)
    ticket_revenue = 0.0
    flat_fee_revenue = 0.0
    other_revenue = 0.0

    shows_with_financials.each do |show|
      next unless show.show_financials&.has_data?

      shows_with_data += 1
      financials = show.show_financials
      gross_revenue += financials.total_revenue
      show_expenses += financials.calculated_expenses
      production_expenses += financials.calculated_production_expenses

      # Track revenue by type
      if financials.ticket_sales?
        ticket_revenue += financials.ticket_revenue
      else
        flat_fee_revenue += financials.flat_fee.to_f
      end
      other_revenue += financials.calculated_other_revenue

      # Track expenses by category
      financials.normalized_expense_details.each do |item|
        category = item["category"].presence || "other"
        expense_by_category[category] += item["amount"].to_f
      end
      # If no detailed expenses but has a raw expense amount
      if financials.normalized_expense_details.empty? && financials.expenses.to_f > 0
        expense_by_category["other"] += financials.expenses.to_f
      end
    end

    # Get payout totals (performer payouts are part of Cost of Shows)
    show_ids = scope.pluck(:id)
    total_payouts = ShowPayout.where(show_id: show_ids).sum(:total_payout) || 0

    # Also include production expenses for shows that may not have financial data yet
    # (production expenses are allocated to all shows regardless of whether financials are entered)
    if production_expenses == 0 && @productions.any?
      production_expense_total = ProductionExpenseAllocation
        .joins(:show)
        .where(shows: { id: show_ids })
        .sum(:allocated_amount)
      production_expenses = production_expense_total.to_f
    end

    # Cost of Shows = Show Expenses + Production Expenses (Allocated) + Performer Payouts (direct costs)
    cost_of_shows = show_expenses + production_expenses + total_payouts

    # Gross Profit = Revenue - Cost of Shows
    gross_profit = gross_revenue - cost_of_shows
    gross_margin = gross_revenue > 0 ? (gross_profit / gross_revenue * 100).round(1) : 0

    # For now, we don't track operating expenses separately, so Net Income = Gross Profit
    # In future, operating_expenses would be subtracted here
    net_income = gross_profit

    # Contract revenue (incoming payments from contracts)
    contract_revenue = calculate_contract_revenue(production_ids, date_range)

    {
      show_count: scope.count,
      shows_with_data: shows_with_data,
      gross_revenue: gross_revenue,
      show_expenses: show_expenses,
      production_expenses: production_expenses,
      total_payouts: total_payouts,
      cost_of_shows: cost_of_shows,
      gross_profit: gross_profit,
      gross_margin: gross_margin,
      net_income: net_income,
      average_revenue_per_show: shows_with_data > 0 ? (gross_revenue / shows_with_data).round(2) : 0,
      # Breakdowns
      ticket_revenue: ticket_revenue,
      flat_fee_revenue: flat_fee_revenue,
      other_revenue: other_revenue,
      contract_revenue: contract_revenue,
      expense_by_category: expense_by_category,
      # Legacy keys for backward compatibility during transition
      total_revenue: gross_revenue,
      total_expenses: show_expenses,
      net_profit: gross_profit,
      profit_margin: gross_margin,
      retained: net_income
    }
  end

  def calculate_contract_revenue(production_ids, date_range)
    # Contracts belong to organizations, not productions.
    # Get the organization IDs from the productions.
    org_ids = Production.where(id: production_ids).pluck(:organization_id).uniq
    scope = Contract.where(organization_id: org_ids).where(status: :active)

    if date_range
      # Only include contracts that overlap with the date range
      scope = scope.where("contract_start_date <= ? OR contract_start_date IS NULL", date_range.last)
                   .where("contract_end_date >= ? OR contract_end_date IS NULL", date_range.first)
    end

    # Only count payments that have actually been paid
    scope.sum { |contract| contract.contract_payments.where(direction: "incoming").status_paid.sum(:amount) }
  rescue
    0.0
  end
end
