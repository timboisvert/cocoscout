# frozen_string_literal: true

module Manage
  class ShowPayoutsController < Manage::ManageController
    before_action :set_production
    before_action :set_show_payout, only: [
      :show, :update, :edit_financials, :update_financials,
      :calculate, :approve, :mark_paid, :revert_to_draft,
      :override, :save_override, :clear_override,
      :mark_line_item_paid, :unmark_line_item_paid
    ]

    def index
      @filter = params[:filter] || "all"

      base_scope = @production.shows
                              .order(date_and_time: :desc)
                              .includes(:show_financials, show_payout: :line_items)

      # Default: non-canceled shows only (except for canceled filter)
      shows_scope = @filter == "canceled" ? base_scope.where(canceled: true) : base_scope.where(canceled: false)

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
      when "canceled"
        # All canceled shows (already filtered above)
        @shows = shows_scope
      else
        # All past non-canceled shows
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
        redirect_to manage_production_money_show_payout_path(@production, @show),
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
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Financial data saved."
      else
        render :edit_financials, status: :unprocessable_entity
      end
    end

    def calculate
      # Ensure we have financials
      unless @show.show_financials&.complete?
        redirect_to manage_production_edit_financials_money_show_payout_path(@production, @show),
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

        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payouts calculated: #{helpers.number_to_currency(result[:total])} total."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    alert: "Could not calculate payouts: #{result[:error]}"
      end
    end

    def approve
      if @show_payout.approve!(Current.user)
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payout approved and locked."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    alert: "Could not approve payout."
      end
    end

    def mark_paid
      if @show_payout.mark_paid!
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payout marked as paid."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    alert: "Could not mark as paid."
      end
    end

    def revert_to_draft
      if @show_payout.revert_to_draft!
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payout reverted to draft for editing."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    alert: "Could not revert payout."
      end
    end

    def override
      @default_scheme = @production.payout_schemes.find_by(is_default: true)
      @current_rules = @show_payout.override_rules.presence || @default_scheme&.rules || {}
    end

    def save_override
      rules = build_override_rules
      @show_payout.update!(override_rules: rules)
      redirect_to manage_production_money_show_payout_path(@production, @show),
                  notice: "Custom rules saved for this show."
    end

    def clear_override
      @show_payout.update!(override_rules: nil)
      redirect_to manage_production_money_show_payout_path(@production, @show),
                  notice: "Custom rules cleared. Using default scheme."
    end

    def mark_line_item_paid
      line_item = @show_payout.line_items.find(params[:line_item_id])
      line_item.mark_as_already_paid!(Current.user)
      redirect_to manage_production_money_show_payout_path(@production, @show),
                  notice: "#{line_item.payee_name} marked as already paid."
    end

    def unmark_line_item_paid
      line_item = @show_payout.line_items.find(params[:line_item_id])
      line_item.unmark_as_already_paid!
      redirect_to manage_production_money_show_payout_path(@production, @show),
                  notice: "#{line_item.payee_name} no longer marked as already paid."
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
      params.require(:show_payout).permit(:notes, :payout_scheme_id)
    end

    def show_financials_params
      params.require(:show_financials).permit(:ticket_count, :ticket_revenue, :other_revenue, :expenses, :notes)
    end

    def override_rules_params
      params.require(:override_rules).permit!
    end

    def build_override_rules
      rules_params = params[:override_rules] || {}
      distribution_params = rules_params[:distribution] || {}
      method = distribution_params[:method] || "per_ticket_guaranteed"

      # Build distribution
      distribution = { "method" => method }

      case method
      when "per_ticket_guaranteed"
        distribution["per_ticket_rate"] = distribution_params[:per_ticket_rate]&.to_f || 1.0
        distribution["minimum"] = distribution_params[:minimum]&.to_f || 0
      when "flat_fee"
        distribution["flat_amount"] = distribution_params[:flat_amount]&.to_f || 0
      when "custom"
        # Custom per-person: use flat_fee method with all amounts in performer_overrides
        distribution = { "method" => "flat_fee", "flat_amount" => 0 }
      end

      # Build performer overrides
      performer_overrides = {}
      overrides_params = rules_params[:performer_overrides] || {}
      overrides_params.each do |person_id, override_data|
        next if person_id.blank?

        override = {}
        override["per_ticket_rate"] = override_data[:per_ticket_rate].to_f if override_data[:per_ticket_rate].present?
        override["minimum"] = override_data[:minimum].to_f if override_data[:minimum].present?
        override["flat_amount"] = override_data[:flat_amount].to_f if override_data[:flat_amount].present?

        performer_overrides[person_id.to_s] = override if override.any?
      end

      {
        "allocation" => [],
        "distribution" => distribution,
        "performer_overrides" => performer_overrides
      }
    end
  end
end
