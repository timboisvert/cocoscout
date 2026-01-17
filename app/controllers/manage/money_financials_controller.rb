# frozen_string_literal: true

module Manage
  class MoneyFinancialsController < Manage::ManageController
    before_action :set_production

    def index
      # Financial summary for selected period
      @selected_period = (params[:period].presence || "all_time").to_sym
      @financial_summary = FinancialSummaryService.new(@production)
                                                   .summary_for_period(@selected_period)

      # Get shows with financial data - include all past events
      @shows = @production.shows
                          .where("date_and_time <= ?", 1.day.from_now)
                          .order(date_and_time: :desc)
                          .includes(:show_financials, :location)
                          .limit(50)

      # Apply filter if provided
      @filter = params[:filter].presence || "all"
      @shows = apply_filter(@shows, @filter)

      # Persist hide_non_revenue preference in cookie
      if params[:hide_non_revenue].present?
        @hide_non_revenue = params[:hide_non_revenue] == "true"
        cookies[:money_hide_non_revenue] = { value: @hide_non_revenue.to_s, expires: 1.year.from_now }
      else
        @hide_non_revenue = cookies[:money_hide_non_revenue] != "false"
      end

      # Filter out non-revenue events if toggle is on
      if @hide_non_revenue
        @shows = @shows.where(event_type: EventTypes.revenue_event_types)
      end

      # Summary stats for financials
      revenue_types = EventTypes.revenue_event_types
      @revenue_events_count = @production.shows
                                          .where(event_type: revenue_types)
                                          .where("date_and_time <= ?", 1.day.from_now)
                                          .count

      @financials_complete_count = @production.shows
                                               .where(event_type: revenue_types)
                                               .where("date_and_time <= ?", 1.day.from_now)
                                               .joins(:show_financials)
                                               .where(show_financials: { data_confirmed: true })
                                               .count

      @financials_pending_count = @revenue_events_count - @financials_complete_count
    end

    private

    def set_production
      @production = Current.production
      redirect_to select_production_path unless @production
    end

    def apply_filter(scope, filter)
      case filter
      when "complete"
        scope.joins(:show_financials)
             .where(show_financials: { data_confirmed: true })
      when "pending"
        revenue_types = EventTypes.revenue_event_types
        scope.where(event_type: revenue_types)
             .left_joins(:show_financials)
             .where("show_financials.id IS NULL OR show_financials.data_confirmed = FALSE")
      when "non_revenue"
        revenue_types = EventTypes.revenue_event_types
        scope.where.not(event_type: revenue_types)
             .or(scope.joins(:show_financials).where(show_financials: { non_revenue_override: true }))
      else
        scope
      end
    end
  end
end
