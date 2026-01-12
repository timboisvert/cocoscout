# frozen_string_literal: true

class FinancialSummaryService
  PERIODS = {
    this_week: -> { Time.current.beginning_of_week..Time.current.end_of_week },
    this_month: -> { Time.current.beginning_of_month..Time.current.end_of_month },
    last_30_days: -> { 30.days.ago.beginning_of_day..Time.current.end_of_day },
    this_year: -> { Time.current.beginning_of_year..Time.current.end_of_year },
    all_time: -> { nil }
  }.freeze

  PERIOD_LABELS = {
    this_week: "This Week",
    this_month: "This Month",
    last_30_days: "Last 30 Days",
    this_year: "This Year",
    all_time: "All Time"
  }.freeze

  def initialize(production)
    @production = production
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
    total_revenue = 0.0
    total_expenses = 0.0
    shows_with_data = 0

    shows_with_financials.each do |show|
      next unless show.show_financials&.has_data?

      shows_with_data += 1
      total_revenue += show.show_financials.total_revenue
      total_expenses += show.show_financials.calculated_expenses
    end

    net_profit = total_revenue - total_expenses
    profit_margin = total_revenue > 0 ? (net_profit / total_revenue * 100).round(1) : 0

    # Get payout totals
    show_ids = scope.pluck(:id)
    total_payouts = ShowPayout.where(show_id: show_ids).sum(:total_payout) || 0
    retained = net_profit - total_payouts

    {
      show_count: scope.count,
      shows_with_data: shows_with_data,
      total_revenue: total_revenue,
      total_expenses: total_expenses,
      net_profit: net_profit,
      profit_margin: profit_margin,
      total_payouts: total_payouts,
      retained: retained,
      average_revenue_per_show: shows_with_data > 0 ? (total_revenue / shows_with_data).round(2) : 0
    }
  end
end
