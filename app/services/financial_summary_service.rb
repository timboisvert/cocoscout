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

  def initialize(production)
    @production = production
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

    scope = @production.shows
                       .where(canceled: false)
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
    shows_with_data = 0

    shows_with_financials.each do |show|
      next unless show.show_financials&.has_data?

      shows_with_data += 1
      gross_revenue += show.show_financials.total_revenue
      show_expenses += show.show_financials.calculated_expenses
    end

    # Get payout totals (performer payouts are part of Cost of Shows)
    show_ids = scope.pluck(:id)
    total_payouts = ShowPayout.where(show_id: show_ids).sum(:total_payout) || 0

    # Cost of Shows = Show Expenses + Performer Payouts (direct costs)
    cost_of_shows = show_expenses + total_payouts

    # Gross Profit = Revenue - Cost of Shows
    gross_profit = gross_revenue - cost_of_shows
    gross_margin = gross_revenue > 0 ? (gross_profit / gross_revenue * 100).round(1) : 0

    # For now, we don't track operating expenses separately, so Net Income = Gross Profit
    # In future, operating_expenses would be subtracted here
    net_income = gross_profit

    {
      show_count: scope.count,
      shows_with_data: shows_with_data,
      gross_revenue: gross_revenue,
      show_expenses: show_expenses,
      total_payouts: total_payouts,
      cost_of_shows: cost_of_shows,
      gross_profit: gross_profit,
      gross_margin: gross_margin,
      net_income: net_income,
      average_revenue_per_show: shows_with_data > 0 ? (gross_revenue / shows_with_data).round(2) : 0,
      # Legacy keys for backward compatibility during transition
      total_revenue: gross_revenue,
      total_expenses: show_expenses,
      net_profit: gross_profit,
      profit_margin: gross_margin,
      retained: net_income
    }
  end
end
