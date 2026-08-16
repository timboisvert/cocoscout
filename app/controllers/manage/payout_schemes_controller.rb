# frozen_string_literal: true

module Manage
  class PayoutSchemesController < Manage::ManageController
    before_action :set_payout_scheme, only: [ :show, :edit, :update, :destroy, :make_default, :update_defaults, :archive, :unarchive ]

    def index
      # Show all payout schemes for the organization (both org-level and production-level)
      @show_archived = params[:archived] == "1"
      @payout_schemes = Current.organization.payout_schemes
                                            .then { |schemes| @show_archived ? schemes.archived : schemes.active }
                                            .default_first
                                            .includes(:production, payout_scheme_defaults: :production)
      @archived_count = Current.organization.payout_schemes.archived.count
    end

    def show
      @show_payouts = @payout_scheme.show_payouts.includes(:show).order("shows.date_and_time DESC").limit(10)
    end

    def new
      @payout_scheme = PayoutScheme.new(organization: Current.organization)
    end

    def create
      @payout_scheme = PayoutScheme.new(payout_scheme_params)
      @payout_scheme.organization = Current.organization

      if @payout_scheme.save
        # Make default if it's the first org-level scheme
        org_level_count = Current.organization.payout_schemes.organization_level.count
        @payout_scheme.make_default! if org_level_count == 1

        redirect_to manage_money_payout_scheme_path(@payout_scheme),
                    notice: "Payout scheme created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @payout_scheme.update(payout_scheme_params)
        redirect_to manage_money_payout_scheme_path(@payout_scheme),
                    notice: "Payout scheme updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @payout_scheme.show_payouts.paid.any?
        redirect_to manage_money_payout_schemes_path,
                    alert: "Cannot delete a scheme that has been used for paid payouts."
        return
      end

      was_default = @payout_scheme.is_default?
      was_org_level = @payout_scheme.organization_level?
      @payout_scheme.destroy!

      # If we deleted the default, make another one default
      if was_default
        if was_org_level
          Current.organization.payout_schemes.organization_level.first&.make_default!
        elsif @payout_scheme.production.present?
          @payout_scheme.production.payout_schemes.first&.make_default!
        end
      end

      redirect_to manage_money_payout_schemes_path,
                  notice: "Payout scheme deleted."
    end

    def make_default
      # Legacy support: uses old is_default flag
      effective_from = params[:effective_from].presence
      @payout_scheme.update!(effective_from: effective_from) if effective_from.present? || @payout_scheme.effective_from.present?
      @payout_scheme.make_default!

      notice = "#{@payout_scheme.name} is now the default payout scheme"
      notice += " for shows on or after #{@payout_scheme.effective_from.strftime('%-d %B %Y')}" if @payout_scheme.effective_from.present?
      notice += "."

      redirect_to manage_money_payout_schemes_path, notice: notice
    end

    def update_defaults
      production_ids = Array(params[:production_ids]).map(&:to_i).reject(&:zero?)
      effective_from = params[:effective_from].presence&.to_date
      org_level_fallback = params[:org_level_fallback] == "1"

      if org_level_fallback
        # Set as org-level fallback (no specific productions)
        @payout_scheme.set_as_default_for!(production_ids: [], effective_from: effective_from)
        notice = "#{@payout_scheme.name} is now the organization-level default"
      elsif production_ids.any?
        @payout_scheme.set_as_default_for!(production_ids: production_ids, effective_from: effective_from)
        production_names = Production.where(id: production_ids).pluck(:name).join(", ")
        notice = "#{@payout_scheme.name} is now the default for: #{production_names}"
      else
        # Clear all defaults for this scheme
        @payout_scheme.payout_scheme_defaults.destroy_all
        notice = "#{@payout_scheme.name} is no longer a default for any production"
      end

      notice += " (effective #{effective_from.strftime('%-d %B %Y')})" if effective_from.present?
      redirect_to manage_money_payout_scheme_path(@payout_scheme), notice: notice
    end

    # Collection actions for presets
    def presets
      @presets = PayoutScheme::PRESETS
    end

    def create_from_preset
      preset_key = params[:preset_key]&.to_sym

      @payout_scheme = PayoutScheme.create_from_preset(Current.organization, preset_key)

      if @payout_scheme&.persisted?
        # Make default if it's the first org-level scheme
        org_level_count = Current.organization.payout_schemes.organization_level.count
        @payout_scheme.make_default! if org_level_count == 1

        redirect_to manage_edit_money_payout_scheme_path(@payout_scheme),
                    notice: "Created #{@payout_scheme.name}. Customize it below."
      else
        redirect_to manage_money_payout_schemes_path,
                    alert: "Could not create payout scheme from preset."
      end
    end

    def archive
      @payout_scheme.archive!
      redirect_to manage_money_payout_schemes_path,
                  notice: "#{@payout_scheme.name} has been archived."
    end

    def unarchive
      @payout_scheme.unarchive!
      redirect_to manage_money_payout_scheme_path(@payout_scheme),
                  notice: "#{@payout_scheme.name} has been restored."
    end

    private

    def set_payout_scheme
      @payout_scheme = PayoutScheme.where(organization: Current.organization)
                                   .find(params[:id])
    end

    def payout_scheme_params
      base_params = params.require(:payout_scheme).permit(:name, :description, :is_default, :effective_from)

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

      # Add individual allocations (percentage to specific people)
      individual_allocations_params = rules_params[:individual_allocations] || {}
      individual_allocations_params.each do |_index, alloc_data|
        next if alloc_data[:person_id].blank? || alloc_data[:percentage].blank?

        allocation << {
          "type" => "percentage",
          "value" => alloc_data[:percentage].to_f,
          "person_id" => alloc_data[:person_id].to_i,
          "label" => alloc_data[:label].presence || nil
        }
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
      when "per_act"
        act_mode = distribution_params[:act_mode].to_s
        act_mode = "schedule" unless PayoutScheme::ACT_MODES.include?(act_mode)
        distribution["act_mode"] = act_mode

        case act_mode
        when "simple"
          distribution["per_act_rate"] = distribution_params[:per_act_rate]&.to_f || 0
        when "schedule"
          # What each act is worth, in order — the rows are positional, so the
          # first amount is the first act's rate. Plus what every act past the
          # end of the list is worth (blank means those acts pay nothing).
          distribution["act_rates"] = Array(distribution_params[:act_rates])
            .each_with_index
            .map { |amount, index| { "act" => index + 1, "amount" => amount.to_f } }
          distribution["additional_act_rate"] =
            distribution_params[:additional_act_rate].presence&.to_f
        else
          # Each row is "this many acts pays this much"; blank/zero rows are dropped
          # and the table is stored sorted so lookups can walk it in order.
          distribution["tiers"] = Array(distribution_params[:tiers]&.values)
            .filter_map do |tier|
              acts = tier[:acts].to_i
              next if acts <= 0

              { "acts" => acts, "amount" => tier[:amount].to_f }
            end
            .sort_by { |tier| tier["acts"] }
        end
      end

      # Build performer overrides
      performer_overrides = {}
      overrides_params = rules_params[:performer_overrides] || {}
      overrides_params.each do |person_id, override_data|
        next if person_id.blank?

        override = {}
        override["per_ticket_rate"] = override_data[:per_ticket_rate].to_f if override_data[:per_ticket_rate].present?
        override["minimum"] = override_data[:minimum].to_f if override_data[:minimum].present?
        override["shares"] = override_data[:shares].to_f if override_data[:shares].present?
        override["flat_amount"] = override_data[:flat_amount].to_f if override_data[:flat_amount].present?
        override["per_act_rate"] = override_data[:per_act_rate].to_f if override_data[:per_act_rate].present?

        performer_overrides[person_id.to_s] = override if override.any?
      end

      {
        "allocation" => allocation,
        "distribution" => distribution,
        "performer_overrides" => performer_overrides
      }
    end
  end
end
