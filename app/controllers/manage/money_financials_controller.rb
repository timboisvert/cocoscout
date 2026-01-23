# frozen_string_literal: true

module Manage
  class MoneyFinancialsController < Manage::ManageController
    before_action :set_production

    def index
      # Financial summary for selected period
      @selected_period = (params[:period].presence || "all_time").to_sym

      if @production
        # Single production view - show list of shows
        @financial_summary = FinancialSummaryService.new(@production).summary_for_period(@selected_period)
        @shows = load_shows_for_production(@production)
      else
        # All productions view - show list of productions with summaries
        @productions = Current.organization.productions.order(:name)
        @financial_summary = FinancialSummaryService.new(@productions).summary_for_period(@selected_period)
        @production_summaries = @productions.map do |production|
          summary = FinancialSummaryService.new(production).summary_for_period(@selected_period)
          # Build summary in the format the production_row partial expects
          {
            production: production,
            revenue_shows: summary[:show_count],
            gross_revenue: summary[:gross_revenue],
            show_expenses: summary[:show_expenses],
            production_expenses: summary[:production_expenses],
            total_payouts: summary[:total_payouts],
            net_income: summary[:net_income]
          }
        end
      end

      # Apply filter if provided
      @filter = params[:filter].presence || "all"

      if @production && @shows
        @shows = apply_filter(@shows, @filter)

        # Handle hide_non_revenue toggle
        if params[:hide_non_revenue].present?
          @hide_non_revenue = params[:hide_non_revenue] == "true"
          cookies[:money_hide_non_revenue] = { value: @hide_non_revenue.to_s, expires: 1.year.from_now }
        else
          @hide_non_revenue = cookies[:money_hide_non_revenue] != "false"
        end

        if @hide_non_revenue
          revenue_types = EventTypes.revenue_event_types
          @shows = @shows.select { |show| revenue_types.include?(show.event_type) }
        end
      end
    end

    private

    def set_production
      if params[:production_id].present?
        @production = Current.organization.productions.find_by(id: params[:production_id])
      end
    end

    def load_shows_for_production(production)
      production.shows
                .where("date_and_time <= ?", 1.day.from_now)
                .order(date_and_time: :desc)
                .includes(:show_financials, :location)
                .limit(100)
                .to_a
    end

    def apply_filter(scope, filter)
      case filter
      when "complete"
        scope.select { |show| show.show_financials&.data_confirmed? }
      when "pending"
        revenue_types = EventTypes.revenue_event_types
        scope.select do |show|
          revenue_types.include?(show.event_type) && !show.show_financials&.data_confirmed?
        end
      when "non_revenue"
        revenue_types = EventTypes.revenue_event_types
        scope.select { |show| !revenue_types.include?(show.event_type) || show.show_financials&.non_revenue_override? }
      else
        scope
      end
    end
  end
end
