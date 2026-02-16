# frozen_string_literal: true

module Manage
  class ShowFinancialsController < Manage::ManageController
    before_action :set_show
    before_action :set_production
    before_action :set_show_financials

    def show
      @show_payout = @show.show_payout || @show.build_show_payout

      # Load production expense allocations for this show
      @production_expense_allocations = @show.production_expense_allocations
                                             .includes(:production_expense)
                                             .order("production_expenses.name")

      # Calculate comparison metrics for this show type
      @comparison_data = calculate_comparison_data

      # Get recent shows of same type for trends
      @recent_shows = recent_similar_shows
    end

    def edit
      # Renders the financial data entry form (worksheet)
      # This is called via Turbo Frame for modal display
      respond_to do |format|
        format.html { render layout: request.headers["Turbo-Frame"].present? ? false : "application" }
      end
    end

    def update
      if @show_financials.update(show_financials_params)
        respond_to do |format|
          format.html { redirect_to manage_money_show_financials_path(@show), notice: "Financial data saved successfully." }
          format.turbo_stream { redirect_to manage_money_show_financials_path(@show), notice: "Financial data saved successfully." }
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def mark_non_revenue
      @show_financials.update!(non_revenue_override: true, data_confirmed: true)
      redirect_to manage_money_show_financials_path(@show),
                  notice: "#{show_display_name(@show)} marked as non-revenue event."
    end

    def unmark_non_revenue
      @show_financials.update!(non_revenue_override: false)
      redirect_to manage_money_show_financials_path(@show),
                  notice: "#{show_display_name(@show)} restored as revenue event."
    end

    private

    def set_show
      @show = Show.joins(:production)
                  .where(productions: { organization: Current.organization })
                  .find(params[:id])
    end

    def set_production
      @production = @show.production
    end

    def set_show_financials
      @show_financials = @show.show_financials&.tap { |sf| sf.expense_items.load } || @show.build_show_financials
      @show_financials.save! if @show_financials.new_record?
    end

    def require_manage_permission
      authorize_production_action!(:manage)
    end

    def show_financials_params
      permitted = params.require(:show_financials).permit(
        :revenue_type,
        :ticket_count,
        :ticket_revenue,
        :flat_fee,
        :other_revenue,
        :expenses,
        :notes,
        :data_confirmed,
        other_revenue_details: [ :description, :amount ],
        expense_details: [ :category, :description, :amount ],
        expense_items_attributes: [ :id, :category, :description, :amount, :position, :_destroy ]
      )

      # Convert hash-style params to arrays for details fields
      # Rails sends {"0" => {desc: x}, "1" => {desc: y}} but we need [{desc: x}, {desc: y}]
      # Note: permitted params are ActionController::Parameters objects, need deep conversion
      if permitted[:expense_details].present?
        permitted[:expense_details] = permitted[:expense_details].to_unsafe_h.values.map do |v|
          v.is_a?(ActionController::Parameters) ? v.to_unsafe_h : v
        end
      end
      if permitted[:other_revenue_details].present?
        permitted[:other_revenue_details] = permitted[:other_revenue_details].to_unsafe_h.values.map do |v|
          v.is_a?(ActionController::Parameters) ? v.to_unsafe_h : v
        end
      end

      permitted
    end

    def calculate_comparison_data
      # Get shows of the same event type with financial data
      similar_shows = @production.shows
                                 .where(event_type: @show.event_type)
                                 .where(canceled: false)
                                 .where.not(id: @show.id)
                                 .where("date_and_time < ?", Time.current)
                                 .includes(:show_financials)
                                 .select { |s| s.show_financials&.has_data? }

      return nil if similar_shows.empty?

      revenues = similar_shows.map { |s| s.show_financials.total_revenue }
      expenses = similar_shows.map { |s| s.show_financials.calculated_expenses }
      profits = similar_shows.map { |s| s.show_financials.net_revenue }
      ticket_counts = similar_shows.filter_map { |s| s.show_financials.ticket_count if s.show_financials.ticket_sales? }

      {
        count: similar_shows.count,
        avg_revenue: revenues.sum / revenues.count,
        avg_expenses: expenses.sum / expenses.count,
        avg_profit: profits.sum / profits.count,
        avg_tickets: ticket_counts.any? ? ticket_counts.sum / ticket_counts.count : nil,
        max_revenue: revenues.max,
        min_revenue: revenues.min,
        this_show_revenue: @show_financials.total_revenue,
        this_show_profit: @show_financials.net_revenue,
        performance_vs_avg: @show_financials.has_data? && revenues.any? ?
          ((@show_financials.net_revenue - (profits.sum / profits.count)) / (profits.sum / profits.count).abs * 100).round(1) : nil
      }
    end

    def recent_similar_shows
      @production.shows
                 .where(event_type: @show.event_type)
                 .where(canceled: false)
                 .where.not(id: @show.id)
                 .where("date_and_time < ?", Time.current)
                 .includes(:show_financials, :show_payout)
                 .order(date_and_time: :desc)
                 .limit(5)
                 .select { |s| s.show_financials&.has_data? }
    end
  end
end
