# frozen_string_literal: true

module Manage
  class MoneyFinancialsController < Manage::ManageController
    before_action :set_production

    def index
      # Financial summary for selected period
      @selected_period = (params[:period].presence || "all_time").to_sym

      if @production
        # Check if this is a third-party production
        @is_third_party = @production.type_third_party?

        if @is_third_party
          # Third-party production - load contract data
          load_third_party_financials
        else
          # In-house production - show list of shows
          @financial_summary = FinancialSummaryService.new(@production).summary_for_period(@selected_period)
          @shows = load_shows_for_production(@production)
        end
      else
        # All productions view - show list of productions with summaries
        return redirect_to manage_path unless Current.organization

        @productions = Current.organization.productions.order(:name)
        @financial_summary = FinancialSummaryService.new(@productions).summary_for_period(@selected_period)
        @production_summaries = @productions.map do |production|
          if production.type_third_party?
            build_third_party_summary(production)
          else
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
      end

      # Apply filter if provided (only for in-house productions)
      @filter = params[:filter].presence || "all"

      if @production && @shows && !@is_third_party
        @shows = apply_filter(@shows, @filter)

        # Handle hide_future_events toggle (enabled by default)
        if params[:hide_future_events].present?
          @hide_future_events = params[:hide_future_events] == "true"
          cookies[:money_hide_future_events] = { value: @hide_future_events.to_s, expires: 1.year.from_now }
        else
          @hide_future_events = cookies[:money_hide_future_events] != "false"
        end

        if @hide_future_events
          @shows = @shows.select { |show| show.date_and_time <= 1.day.from_now }
        end

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
      return unless Current.organization

      if params[:production_id].present?
        @production = Current.organization.productions.find_by(id: params[:production_id])
      end
    end

    def load_third_party_financials
      @contract = @production.contract

      if @contract
        @contract_payments = @contract.contract_payments.order(:due_date)
        @space_rentals = @contract.space_rentals.includes(:shows).order(:starts_at)

        # Build financial summary for third-party
        received = @contract.total_incoming
        pending_payments = @contract.pending_payments
        overdue_payments = @contract.overdue_payments

        @financial_summary = {
          gross_revenue: received,
          pending_amount: pending_payments.sum(:amount),
          pending_count: pending_payments.count,
          overdue_amount: overdue_payments.sum(:amount),
          overdue_count: overdue_payments.count,
          total_contract_value: @contract_payments.sum(:amount)
        }
      else
        @contract_payments = []
        @space_rentals = []
        @financial_summary = {
          gross_revenue: 0,
          pending_amount: 0,
          pending_count: 0,
          overdue_amount: 0,
          overdue_count: 0,
          total_contract_value: 0
        }
      end
    end

    def build_third_party_summary(production)
      contract = production.contract
      return empty_third_party_summary(production) unless contract

      received = contract.total_incoming
      pending_payments = contract.pending_payments
      overdue_payments = contract.overdue_payments

      {
        production: production,
        is_third_party: true,
        contract: contract,
        total_shows: production.shows.count,
        gross_revenue: received,
        pending_amount: pending_payments.sum(:amount),
        pending_count: pending_payments.count,
        overdue_amount: overdue_payments.sum(:amount),
        overdue_count: overdue_payments.count,
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
