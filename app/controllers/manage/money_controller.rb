# frozen_string_literal: true

module Manage
  class MoneyController < Manage::ManageController
    def index
      # Financial summary for selected period
      @selected_period = (params[:period].presence || "all_time").to_sym

      # Get productions the user has access to
      @productions = Current.user.accessible_productions.order(:name)

      # Build summary data for each production
      @production_summaries = @productions.map do |production|
        build_production_summary(production)
      end

      # Overall organization summary
      @org_summary = FinancialSummaryService.new(@productions).summary_for_period(@selected_period)
    end

    private

    def build_production_summary(production)
      # Third-party productions use contract-based financials
      if production.type_third_party?
        return build_third_party_summary(production)
      end

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

    def build_third_party_summary(production)
      contract = production.contract
      return empty_third_party_summary(production) unless contract

      received = contract.total_incoming
      pending_payments = contract.pending_payments
      pending_amount = pending_payments.sum(:amount)
      overdue_payments = contract.overdue_payments
      overdue_amount = overdue_payments.sum(:amount)

      {
        production: production,
        is_third_party: true,
        contract: contract,
        total_shows: production.shows.count,
        gross_revenue: received,
        pending_amount: pending_amount,
        pending_count: pending_payments.count,
        overdue_amount: overdue_amount,
        overdue_count: overdue_payments.count,
        # Zero out in-house specific fields
        show_expenses: 0,
        production_expenses: 0,
        total_payouts: 0,
        net_income: received
      }
    end

    def empty_third_party_summary(production)
      {
        production: production,
        is_third_party: true,
        contract: nil,
        total_shows: production.shows.count,
        gross_revenue: 0,
        pending_amount: 0,
        pending_count: 0,
        overdue_amount: 0,
        overdue_count: 0,
        show_expenses: 0,
        production_expenses: 0,
        total_payouts: 0,
        net_income: 0
      }
    end
  end
end
