# frozen_string_literal: true

module Manage
  class MoneyController < Manage::ManageController
    def index
      # Financial summary for selected period
      @selected_period = (params[:period].presence || "all_time").to_sym

      # Production type filter (sanitize to valid values only)
      @production_filter = %w[all first_party third_party].include?(params[:production_filter]) ? params[:production_filter] : "all"

      # Show all toggle (bypasses relevance filtering)
      @show_all = params[:show_all] == "true"

      # Get productions the user has access to (exclude courses from main list)
      all_productions = Current.user.accessible_productions
        .where.not(production_type: "course")
        .includes(:logo_attachment, :contract)
        .order(:name)

      # Apply production type filter
      @productions = case @production_filter
      when "first_party"
        all_productions.type_in_house
      when "third_party"
        all_productions.type_third_party
      else
        all_productions
      end

      # Apply 3-month relevance filter unless "show all" is toggled
      unless @show_all
        relevant_production_ids = Show.where("date_and_time > ?", 3.months.ago)
                                      .select(:production_id).distinct
        @all_count = @productions.count
        @productions = @productions.where(id: relevant_production_ids)
        @hidden_count = @all_count - @productions.count
      end

      # Build summary data for each production with caching
      cache_key = "money_summaries_#{Current.organization.id}_#{@production_filter}_#{@selected_period}_#{@show_all}"
      cached_data = Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
        { data: @productions.map { |production| build_production_summary(production) }, cached_at: Time.current.iso8601 }
      end
      if cached_data.is_a?(Hash) && cached_data.key?(:data)
        @production_summaries = cached_data[:data]
        @cached_at = cached_data[:cached_at]
      else
        @production_summaries = cached_data
        @cached_at = nil
      end

      # Courses (separate collapsed section)
      @courses = Current.user.accessible_productions
        .where(production_type: "course")
        .includes(:logo_attachment, :contract)
        .order(:name)
      @course_summaries = Rails.cache.fetch("#{cache_key}_courses", expires_in: 15.minutes) do
        @courses.map do |course|
          summary = build_production_summary(course)
          # Enrich with course payout info
          offering = course.course_offerings.first
          if offering
            payout = offering.course_offering_payout
            confirmed_revenue = offering.course_registrations.confirmed.sum(:amount_cents)
            summary[:course_offering] = offering
            summary[:course_confirmed_revenue_cents] = confirmed_revenue
            summary[:course_payout_status] = payout&.status
            summary[:course_payout_total_cents] = payout&.total_payout_cents
          end
          summary
        end
      end

      # Overall organization summary (uses filtered productions)
      @org_summary = FinancialSummaryService.new(@productions).summary_for_period(@selected_period)
    end

    def refresh
      # Clear all financial summary cache variants
      organization_id = Current.organization.id
      periods = FinancialSummaryService::PERIOD_LABELS.keys.map(&:to_s)
      periods.each do |period|
        %w[all first_party third_party].each do |filter|
          [ true, false ].each do |show_all|
            cache_key = "money_summaries_#{organization_id}_#{filter}_#{period}_#{show_all}"
            Rails.cache.delete(cache_key)
            Rails.cache.delete("#{cache_key}_courses")
          end
        end
      end

      respond_to do |format|
        format.json { render json: { success: true } }
        format.html { redirect_to manage_money_index_path(period: params[:period], production_filter: params[:production_filter]), notice: "Financials refreshed successfully" }
      end
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

      # Check for revenue share
      payment_structure = contract.draft_payment_structure
      is_revenue_share = payment_structure == "revenue_share"
      is_ticket_revenue_minus_fee = contract.ticket_revenue_minus_fee?
      payment_config = contract.draft_payment_config
      our_share = is_revenue_share ? payment_config["revenue_our_share"].to_i : nil
      their_share = is_revenue_share ? payment_config["revenue_their_share"].to_i : nil

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
        contract: contract,
        total_shows: production.shows.count,
        gross_revenue: gross_revenue,
        pending_amount: pending_amount,
        pending_count: pending_payments.count,
        overdue_amount: overdue_amount,
        overdue_count: overdue_payments.count,
        is_revenue_share: is_revenue_share,
        is_ticket_revenue_minus_fee: is_ticket_revenue_minus_fee,
        our_share: our_share,
        their_share: their_share,
        flat_fee_amount: is_ticket_revenue_minus_fee ? contract.flat_fee_amount : nil,
        confirmed_show_count: confirmed_count,
        pending_show_count: pending_show_count,
        # Zero out in-house specific fields
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
        contract: nil,
        total_shows: production.shows.count,
        gross_revenue: 0,
        pending_amount: 0,
        pending_count: 0,
        overdue_amount: 0,
        overdue_count: 0,
        is_revenue_share: false,
        our_share: nil,
        their_share: nil,
        show_expenses: 0,
        production_expenses: 0,
        total_payouts: 0,
        net_income: 0
      }
    end
  end
end
