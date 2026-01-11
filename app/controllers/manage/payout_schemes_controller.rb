# frozen_string_literal: true

module Manage
  class PayoutSchemesController < Manage::ManageController
    before_action :set_production
    before_action :set_payout_scheme, only: [ :show, :edit, :update, :destroy, :make_default, :preview ]

    def index
      @payout_schemes = @production.payout_schemes.default_first
    end

    def show
      @show_payouts = @payout_scheme.show_payouts.includes(:show).order("shows.date_and_time DESC").limit(10)
    end

    def new
      @payout_scheme = @production.payout_schemes.new
    end

    def create
      @payout_scheme = @production.payout_schemes.new(payout_scheme_params)

      if @payout_scheme.save
        # Make default if it's the first scheme
        @payout_scheme.make_default! if @production.payout_schemes.count == 1

        redirect_to manage_production_money_payout_scheme_path(@production, @payout_scheme),
                    notice: "Payout scheme created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @payout_scheme.update(payout_scheme_params)
        redirect_to manage_production_money_payout_scheme_path(@production, @payout_scheme),
                    notice: "Payout scheme updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @payout_scheme.show_payouts.not_draft.any?
        redirect_to manage_production_money_payout_schemes_path(@production),
                    alert: "Cannot delete a scheme that has been used for approved payouts."
        return
      end

      was_default = @payout_scheme.is_default?
      @payout_scheme.destroy!

      # If we deleted the default, make another one default
      if was_default
        @production.payout_schemes.first&.make_default!
      end

      redirect_to manage_production_money_payout_schemes_path(@production),
                  notice: "Payout scheme deleted."
    end

    def make_default
      @payout_scheme.make_default!
      redirect_to manage_production_money_payout_schemes_path(@production),
                  notice: "#{@payout_scheme.name} is now the default payout scheme."
    end

    def preview
      # Build sample calculation for preview
      @sample_inputs = {
        ticket_count: params[:ticket_count]&.to_i || 50,
        ticket_revenue: params[:ticket_revenue]&.to_f || 500.0,
        performer_count: params[:performer_count]&.to_i || 4
      }

      @preview_result = PayoutCalculator.preview(
        rules: @payout_scheme.rules,
        financials: @sample_inputs,
        performer_count: @sample_inputs[:performer_count]
      )

      respond_to do |format|
        format.html
        format.json { render json: @preview_result }
      end
    end

    # Collection actions for presets
    def presets
      @presets = PayoutScheme::PRESETS
    end

    def create_from_preset
      preset_key = params[:preset_key]&.to_sym

      @payout_scheme = PayoutScheme.create_from_preset(@production, preset_key)

      if @payout_scheme&.persisted?
        # Make default if it's the first scheme
        @payout_scheme.make_default! if @production.payout_schemes.count == 1

        redirect_to edit_manage_production_money_payout_scheme_path(@production, @payout_scheme),
                    notice: "Created #{@payout_scheme.name}. Customize it below."
      else
        redirect_to manage_production_money_payout_schemes_path(@production),
                    alert: "Could not create payout scheme from preset."
      end
    end

    private

    def set_production
      @production = Current.production
    end

    def set_payout_scheme
      @payout_scheme = @production.payout_schemes.find(params[:id])
    end

    def payout_scheme_params
      base_params = params.require(:payout_scheme).permit(:name, :description, :is_default)

      # Build rules from form inputs
      rules = build_rules_from_params
      base_params.merge(rules: rules)
    end

    def build_rules_from_params
      rules_params = params[:rules] || {}
      distribution_params = rules_params[:distribution] || {}

      method = distribution_params[:method] || "equal"

      # Build allocation
      allocation = []
      if params[:expenses_first] == "1"
        allocation << { "type" => "expenses_first" }
      end
      if params[:house_percentage].present? && params[:house_percentage].to_f > 0
        allocation << { "type" => "percentage", "value" => params[:house_percentage].to_f, "label" => "House take" }
      end
      allocation << { "type" => "remainder", "label" => "Performer pool" }

      # Build distribution
      distribution = { "method" => method }

      case method
      when "shares"
        distribution["default_shares"] = distribution_params[:default_shares]&.to_f || 1.0
      when "per_ticket"
        distribution["per_ticket_rate"] = distribution_params[:per_ticket_rate]&.to_f || 1.0
      when "per_ticket_guaranteed"
        distribution["per_ticket_rate"] = distribution_params[:per_ticket_rate]&.to_f || 1.0
        distribution["minimum"] = distribution_params[:minimum]&.to_f || 0
      when "flat_fee"
        distribution["flat_amount"] = distribution_params[:flat_amount]&.to_f || 0
      end

      {
        "allocation" => allocation,
        "distribution" => distribution,
        "performer_overrides" => {}
      }
    end
  end
end
