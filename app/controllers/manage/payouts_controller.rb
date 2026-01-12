# frozen_string_literal: true

module Manage
  class PayoutsController < Manage::ManageController
    before_action :set_production

    def index
      @payout_schemes = @production.payout_schemes.default_first
      @default_scheme = @payout_schemes.find(&:is_default)

      # Financial summary for selected period
      @selected_period = (params[:period].presence || "last_30_days").to_sym
      @financial_summary = FinancialSummaryService.new(@production)
                                                   .summary_for_period(@selected_period)

      # Get shows with payout status - include all past events
      @shows = @production.shows
                          .where(canceled: false)
                          .where("date_and_time <= ?", 1.day.from_now)
                          .order(date_and_time: :desc)
                          .includes(:show_financials, :show_payout, :location)
                          .limit(50)

      # Apply filter if provided
      @filter = params[:filter].presence || "all"
      @shows = apply_filter(@shows, @filter)

      # Summary stats
      @total_approved = @production.show_payouts.approved.sum(:total_payout) || 0
      @total_paid = @production.show_payouts.paid.sum(:total_payout) || 0
      @pending_count = @production.show_payouts.drafts.count
    end

    private

    def set_production
      @production = Current.production
    end

    def apply_filter(scope, filter)
      case filter
      when "needs_data"
        # Revenue events without complete financial data
        revenue_types = EventTypes.revenue_event_types
        scope.where(event_type: revenue_types)
             .left_joins(:show_financials)
             .where("show_financials.id IS NULL OR (show_financials.data_confirmed = FALSE AND (show_financials.ticket_revenue IS NULL OR show_financials.ticket_revenue = 0) AND (show_financials.flat_fee IS NULL OR show_financials.flat_fee = 0))")
      when "pending"
        scope.joins(:show_payout)
             .where(show_payouts: { status: "draft" })
             .where.not(show_payouts: { calculated_at: nil })
      when "approved"
        scope.joins(:show_payout).where(show_payouts: { status: "approved" })
      when "paid"
        scope.joins(:show_payout).where(show_payouts: { status: "paid" })
      else
        scope
      end
    end
  end
end
