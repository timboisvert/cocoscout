# frozen_string_literal: true

module Manage
  class MoneyController < Manage::ManageController
    def index
      # Financial summary for selected period
      @selected_period = (params[:period].presence || "all_time").to_sym

      # Get all productions for the current organization
      @productions = Current.organization.productions.order(:name)

      # Build summary data for each production
      @production_summaries = @productions.map do |production|
        build_production_summary(production)
      end

      # Overall organization summary
      @org_summary = FinancialSummaryService.new(@productions).summary_for_period(@selected_period)
    end

    private

    def build_production_summary(production)
      revenue_types = EventTypes.revenue_event_types
      shows = production.shows.where("date_and_time <= ?", 1.day.from_now)
      revenue_shows = shows.where(event_type: revenue_types)

      # Get financial summary
      financial_summary = FinancialSummaryService.new(production).summary_for_period(:all_time)

      # Payout stats
      show_payouts = production.show_payouts
      awaiting_payout = show_payouts.where(status: "awaiting_payout").where.not(calculated_at: nil)
      paid_payouts = show_payouts.paid

      # Pending action counts
      awaiting_financials_count = revenue_shows.left_joins(:show_financials)
        .where("show_financials.id IS NULL OR (show_financials.data_confirmed = FALSE AND show_financials.ticket_revenue = 0 AND show_financials.flat_fee = 0)")
        .count

      awaiting_calculation_count = revenue_shows
        .left_joins(:show_payout)
        .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
        .count

      {
        production: production,
        total_shows: shows.count,
        revenue_shows: revenue_shows.count,
        gross_revenue: financial_summary[:gross_revenue],
        show_expenses: financial_summary[:show_expenses],
        production_expenses: financial_summary[:production_expenses],
        total_payouts: financial_summary[:total_payouts],
        net_income: financial_summary[:net_income],
        awaiting_financials_count: awaiting_financials_count,
        awaiting_calculation_count: awaiting_calculation_count,
        awaiting_payout_count: awaiting_payout.count,
        awaiting_payout_amount: awaiting_payout.sum(:total_payout) || 0,
        paid_count: paid_payouts.count,
        paid_amount: paid_payouts.sum(:total_payout) || 0
      }
    end
  end
end
