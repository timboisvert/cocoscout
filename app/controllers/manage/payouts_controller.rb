# frozen_string_literal: true

module Manage
  class PayoutsController < Manage::ManageController
    before_action :set_production

    def index
      @payout_schemes = @production.payout_schemes.default_first
      @default_scheme = @payout_schemes.find(&:is_default)

      # Handle hide_non_revenue toggle with cookie persistence
      if params[:hide_non_revenue].present?
        @hide_non_revenue = params[:hide_non_revenue] == "true"
        cookies[:money_hide_non_revenue] = { value: @hide_non_revenue.to_s, expires: 1.year.from_now }
      else
        @hide_non_revenue = cookies[:money_hide_non_revenue] != "false"
      end

      # Get shows with payout status - include all past events (including canceled)
      @shows = @production.shows
                          .where("date_and_time <= ?", 1.day.from_now)
                          .order(date_and_time: :desc)
                          .includes(:show_financials, :show_payout, :location)
                          .limit(50)

      # Filter out non-revenue events if toggle is on
      if @hide_non_revenue
        @shows = @shows.where(event_type: EventTypes.revenue_event_types)
      end

      # Apply filter if provided
      @filter = params[:filter].presence || "all"
      @selected_period = (params[:period].presence || "all_time").to_sym
      @shows = apply_filter(@shows, @filter)
    end

    private

    def set_production
      @production = Current.production
      redirect_to select_production_path unless @production
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
