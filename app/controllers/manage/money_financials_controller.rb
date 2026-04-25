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
        @is_course = @production.production_type == "course"

        if @is_course
          # Course production - load course offering for payout info
          @course_offering = @production.course_offerings.includes(feature_credit_redemption: :feature_credit).first
          @financial_summary = FinancialSummaryService.new(@production).summary_for_period(@selected_period)
          @shows = load_shows_for_production(@production)
        elsif @is_third_party
          # Third-party production - load contract data AND shows for financial entry
          load_third_party_financials
          @shows = load_shows_for_production(@production)
        else
          # In-house production - show list of shows
          @financial_summary = FinancialSummaryService.new(@production).summary_for_period(@selected_period)
          @shows = load_shows_for_production(@production)
        end
      else
        # All productions view - show list of productions with summaries
        return redirect_to manage_path unless Current.organization

        @productions = Current.user.accessible_productions.order(:name)
        @financial_summary = FinancialSummaryService.new(@productions).summary_for_period(@selected_period)

        revenue_types = EventTypes.revenue_event_types
        # Pre-compute pending show counts per production in bulk
        pending_counts = Show
          .where(production_id: @productions.map(&:id), event_type: revenue_types)
          .where("date_and_time <= ?", 1.day.from_now)
          .left_joins(:show_financials)
          .where("show_financials.id IS NULL OR show_financials.data_confirmed = FALSE OR show_financials.data_confirmed IS NULL")
          .group(:production_id)
          .count

        all_summaries = @productions.map do |production|
          base = if production.type_third_party?
            build_third_party_summary(production)
          else
            summary = FinancialSummaryService.new(production).summary_for_period(@selected_period)
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
          base.merge(pending_financials_count: pending_counts[production.id] || 0)
        end

        @financials_filter = params[:filter].presence
        @production_summaries = @financials_filter == "pending" \
          ? all_summaries.select { |s| s[:pending_financials_count] > 0 }
          : all_summaries
      end

      # Apply filter if provided (for both in-house and third-party productions with shows)
      @filter = params[:filter].presence || "all"

      if @production && @shows
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
        if @contract.ticket_revenue_minus_fee?
          fee_summary = @contract.flat_fee_revenue_summary
          received_fee = @contract.flat_fee_amount
          outgoing_paid = @contract.contract_payments.where(direction: "outgoing").status_paid.sum(:amount)

          @financial_summary = {
            gross_revenue: fee_summary ? fee_summary[:confirmed_revenue] : 0,
            our_fee: received_fee,
            contractor_paid: outgoing_paid,
            pending_amount: @contract.pending_payments.sum(:amount),
            pending_count: @contract.pending_payments.count,
            overdue_amount: @contract.overdue_payments.sum(:amount),
            overdue_count: @contract.overdue_payments.count,
            total_contract_value: received_fee,
            is_ticket_revenue_minus_fee: true,
            confirmed_show_count: fee_summary&.dig(:confirmed_count) || 0,
            pending_show_count: fee_summary&.dig(:pending_count) || 0
          }
        else
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
        end
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

      # Check for revenue share
      is_revenue_share = contract.revenue_share?
      is_ticket_revenue_minus_fee = contract.ticket_revenue_minus_fee?
      our_share = is_revenue_share ? contract.draft_payment_config["revenue_our_share"].to_i : nil

      # For revenue share contracts, calculate from show financials
      show_revenue = 0
      confirmed_count = 0
      pending_show_count = 0
      if is_revenue_share
        rev_summary = contract.revenue_share_summary
        if rev_summary
          show_revenue = rev_summary[:confirmed_revenue]
          confirmed_count = rev_summary[:confirmed_count]
          pending_show_count = rev_summary[:pending_count]
        end
      elsif is_ticket_revenue_minus_fee
        fee_summary = contract.flat_fee_revenue_summary
        if fee_summary
          show_revenue = fee_summary[:confirmed_revenue]
          confirmed_count = fee_summary[:confirmed_count]
          pending_show_count = fee_summary[:pending_count]
        end
      end

      # Calculate gross_revenue and net_income based on contract type
      if is_revenue_share
        gross_revenue = show_revenue
        net_income = (show_revenue * (our_share || 0) / 100.0).round(2)
      elsif is_ticket_revenue_minus_fee
        gross_revenue = show_revenue
        net_income = contract.flat_fee_amount
      else
        gross_revenue = received
        net_income = received
      end

      {
        production: production,
        is_third_party: true,
        is_revenue_share: is_revenue_share,
        is_ticket_revenue_minus_fee: is_ticket_revenue_minus_fee,
        our_share: our_share,
        their_share: is_revenue_share ? contract.contractor_share_percentage.to_i : nil,
        flat_fee_amount: is_ticket_revenue_minus_fee ? contract.flat_fee_amount : nil,
        contract: contract,
        total_shows: production.shows.count,
        gross_revenue: gross_revenue,
        confirmed_show_count: confirmed_count,
        pending_show_count: pending_show_count,
        pending_amount: pending_payments.sum(:amount),
        pending_count: pending_payments.count,
        overdue_amount: overdue_payments.sum(:amount),
        overdue_count: overdue_payments.count,
        show_expenses: 0,
        production_expenses: 0,
        total_payouts: 0,
        net_income: net_income
      }
    end

    def empty_third_party_summary(production)
      {
        production: production,
        is_third_party: true,
        is_revenue_share: false,
        our_share: nil,
        their_share: nil,
        confirmed_show_count: 0,
        pending_show_count: 0,
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
