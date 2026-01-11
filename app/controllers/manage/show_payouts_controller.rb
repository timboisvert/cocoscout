# frozen_string_literal: true

module Manage
  class ShowPayoutsController < Manage::ManageController
    before_action :set_production
    before_action :set_show_payout, only: [
      :show, :update, :edit_financials, :update_financials,
      :calculate, :approve, :mark_paid, :revert_to_draft,
      :override, :save_override, :clear_override
    ]

    def index
      @filter = params[:filter] || "all"

      shows_scope = @production.shows
                               .where(canceled: false)
                               .order(date_and_time: :desc)
                               .includes(:show_financials, show_payout: :line_items)

      case @filter
      when "needs_data"
        # Shows without financials or with incomplete financials
        @shows = shows_scope.left_joins(:show_financials)
                            .where("show_financials.id IS NULL OR show_financials.ticket_count IS NULL OR show_financials.ticket_count = 0")
                            .where("shows.date_and_time < ?", Time.current)
      when "draft"
        @shows = shows_scope.joins(:show_payout).where(show_payouts: { status: "draft" })
      when "approved"
        @shows = shows_scope.joins(:show_payout).where(show_payouts: { status: "approved" })
      when "paid"
        @shows = shows_scope.joins(:show_payout).where(show_payouts: { status: "paid" })
      else
        # All past shows
        @shows = shows_scope.where("shows.date_and_time < ?", Time.current)
      end

      @shows = @shows.limit(50)
    end

    def show
      @line_items = @show_payout.line_items.includes(:payee).by_amount
      @show_financials = @show.show_financials
    end

    def update
      if @show_payout.update(show_payout_params)
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    notice: "Payout updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    def edit_financials
      @show_financials = @show.show_financials || @show.build_show_financials
    end

    def update_financials
      @show_financials = @show.show_financials || @show.build_show_financials
      if @show_financials.update(show_financials_params)
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    notice: "Financial data saved."
      else
        render :edit_financials, status: :unprocessable_entity
      end
    end

    def calculate
      # Ensure we have financials
      unless @show.show_financials&.complete?
        redirect_to edit_financials_manage_production_money_show_payout_path(@production, @show_payout),
                    alert: "Please enter financial data before calculating payouts."
        return
      end

      # Get the scheme to use (with any overrides)
      scheme = @show_payout.payout_scheme || @production.payout_schemes.find_by(is_default: true)
      rules = @show_payout.override_rules.presence || scheme&.rules

      unless rules.present?
        redirect_to manage_production_money_payout_schemes_path(@production),
                    alert: "Please create a payout scheme first."
        return
      end

      # Calculate payouts
      result = PayoutCalculator.calculate(
        show: @show,
        rules: rules
      )

      if result[:success]
        @show_payout.update!(
          calculated_at: Time.current,
          total_payout: result[:total]
        )

        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    notice: "Payouts calculated: #{helpers.number_to_currency(result[:total])} total."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    alert: "Could not calculate payouts: #{result[:error]}"
      end
    end

    def approve
      if @show_payout.approve!(Current.user)
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    notice: "Payout approved and locked."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    alert: "Could not approve payout."
      end
    end

    def mark_paid
      if @show_payout.mark_paid!
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    notice: "Payout marked as paid."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    alert: "Could not mark as paid."
      end
    end

    def revert_to_draft
      if @show_payout.revert_to_draft!
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    notice: "Payout reverted to draft for editing."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                    alert: "Could not revert payout."
      end
    end

    def override
      @default_scheme = @production.payout_schemes.find_by(is_default: true)
      @current_rules = @show_payout.override_rules.presence || @default_scheme&.rules || {}
    end

    def save_override
      @show_payout.update!(override_rules: override_rules_params)
      redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                  notice: "Custom rules saved for this show."
    end

    def clear_override
      @show_payout.update!(override_rules: nil)
      redirect_to manage_production_money_show_payout_path(@production, @show_payout),
                  notice: "Custom rules cleared. Using default scheme."
    end

    private

    def set_production
      @production = Current.production
    end

    def set_show_payout
      # ShowPayout is keyed by show - find or create
      @show = @production.shows.find(params[:id])
      @show_payout = @show.show_payout || @show.create_show_payout!(
        payout_scheme: @production.payout_schemes.find_by(is_default: true),
        status: "draft"
      )
    end

    def show_payout_params
      params.require(:show_payout).permit(:notes)
    end

    def show_financials_params
      params.require(:show_financials).permit(:ticket_count, :ticket_revenue, :other_revenue, :expenses, :notes)
    end

    def override_rules_params
      params.require(:override_rules).permit!
    end
  end
end
