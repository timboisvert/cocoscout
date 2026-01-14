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

      # Summary stats - new terminology
      # Awaiting calculation: shows that need data or haven't been calculated
      revenue_types = EventTypes.revenue_event_types
      revenue_shows = @production.shows.where(event_type: revenue_types).where("date_and_time <= ?", 1.day.from_now)
      @needs_calculation_count = revenue_shows.left_joins(:show_payout)
                                              .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
                                              .count

      # Awaiting payout: calculated but not fully paid
      awaiting_payouts = @production.show_payouts.where(status: "awaiting_payout")
                                                  .where.not(calculated_at: nil)
      @awaiting_payout_count = awaiting_payouts.count
      @total_awaiting_payout = awaiting_payouts.sum(:total_payout) || 0
      @awaiting_payout_people_count = ShowPayoutLineItem.where(show_payout: awaiting_payouts)
                                                         .not_already_paid
                                                         .count

      # Paid out
      paid_payouts = @production.show_payouts.paid
      @paid_shows_count = paid_payouts.count
      @total_paid = paid_payouts.sum(:total_payout) || 0
      @paid_people_count = ShowPayoutLineItem.where(show_payout: paid_payouts)
                                              .already_paid
                                              .count
    end

    private

    def set_production
      @production = Current.production
    end

    def apply_filter(scope, filter)
      case filter
      when "awaiting_financials"
        # Revenue events without complete financial data
        revenue_types = EventTypes.revenue_event_types
        scope.where(event_type: revenue_types)
             .left_joins(:show_financials)
             .where("show_financials.id IS NULL OR (show_financials.data_confirmed = FALSE AND (show_financials.ticket_revenue IS NULL OR show_financials.ticket_revenue = 0) AND (show_financials.flat_fee IS NULL OR show_financials.flat_fee = 0))")
      when "awaiting_calculation"
        # Revenue events with financial data but not yet calculated
        revenue_types = EventTypes.revenue_event_types
        scope.where(event_type: revenue_types)
             .joins(:show_financials)
             .left_joins(:show_payout)
             .where("show_financials.data_confirmed = TRUE OR show_financials.ticket_revenue > 0 OR show_financials.flat_fee > 0")
             .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
      when "awaiting_payout"
        scope.joins(:show_payout)
             .where(show_payouts: { status: "awaiting_payout" })
             .where.not(show_payouts: { calculated_at: nil })
      when "paid"
        scope.joins(:show_payout).where(show_payouts: { status: "paid" })
      else
        scope
      end
    end
  end
end
