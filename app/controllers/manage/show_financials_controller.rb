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
    end

    def edit
      # Renders the financial data entry form (worksheet)
      # This is called via Turbo Frame for modal display
      respond_to do |format|
        format.html { render layout: request.headers["Turbo-Frame"].present? ? false : "application" }
      end
    end

    def update
      handle_cleared_sections

      if @show_financials.update(show_financials_params)
        # Sync to ContractPayments if this is a third-party/contract production
        if @production.type_third_party? && @production.contract&.revenue_share?
          ContractPaymentSyncService.new(@show).call
        end

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
                  notice: "#{@show.display_name} marked as non-revenue event."
    end

    def unmark_non_revenue
      @show_financials.update!(non_revenue_override: false)
      redirect_to manage_money_show_financials_path(@show),
                  notice: "#{@show.display_name} restored as revenue event."
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

    def handle_cleared_sections
      sf_params = params[:show_financials] || {}

      if sf_params[:other_revenue_details_cleared] == "1"
        @show_financials.other_revenue_details = []
        @show_financials.other_revenue = nil
      end

      if sf_params[:expense_items_cleared] == "1"
        # Clear the legacy expense_details JSONB; AR records are handled by _destroy in the nested attributes
        @show_financials.expense_details = []
        @show_financials.expenses = nil
      end
    end

    def show_financials_params
      permitted = params.require(:show_financials).permit(
        :revenue_type,
        :ticket_count,
        :ticket_revenue,
        :flat_fee,
        :other_revenue,
        :contractor_collected,
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
  end
end
