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

      # Arriving from an act-based production (its Pay tab, the casting nudge or
      # a payout page with no scheme yet): start from per-act pay and remember
      # the production so it becomes the default on create.
      @default_production = biased_production
      if @default_production
        @payout_scheme.rules = PayoutScheme::PRESETS[:per_act][:rules].deep_stringify_keys
      end
    end

    def create
      @payout_scheme = PayoutScheme.new(payout_scheme_params)
      @payout_scheme.organization = Current.organization

      if @payout_scheme.save
        # Make default if it's the first org-level scheme
        org_level_count = Current.organization.payout_schemes.organization_level.count
        @payout_scheme.make_default! if org_level_count == 1

        notice = "Payout scheme created successfully."
        if (production = default_production_from_params)
          @payout_scheme.add_default_for_production!(production, effective_from: Date.current)
          notice = "Payout scheme created and set as the default for #{production.name}."
        end

        redirect_to manage_money_payout_scheme_path(@payout_scheme), notice: notice
      else
        @default_production = default_production_from_params
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
      # Only this org's productions — ids come straight from the form.
      production_ids = Current.organization.productions
                              .where(id: Array(params[:production_ids]).map(&:to_i).reject(&:zero?))
                              .pluck(:id)
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

      # Payouts nobody has calculated yet follow the new default instead of the
      # scheme pinned when their page was first opened.
      restamp_scope = org_level_fallback ? Current.organization.productions : Current.organization.productions.where(id: production_ids)
      restamp_scope.find_each { |production| ShowPayout.restamp_pending_for_production!(production, nil) }

      notice += " (effective #{effective_from.strftime('%-d %B %Y')})" if effective_from.present?
      redirect_to manage_money_payout_scheme_path(@payout_scheme), notice: notice
    end

    # Collection actions for presets
    def presets
      @presets = PayoutScheme::PRESETS
      # ?preset=per_act (from an act-based production) puts that preset first
      # and lit up; ?production_id threads through so the scheme becomes that
      # production's default when it's created.
      @highlighted_preset = params[:preset].to_s.to_sym if PayoutScheme::PRESETS.key?(params[:preset].to_s.to_sym)
      @default_production = biased_production
    end

    def create_from_preset
      preset_key = params[:preset_key]&.to_sym

      @payout_scheme = PayoutScheme.create_from_preset(Current.organization, preset_key)

      if @payout_scheme&.persisted?
        # Make default if it's the first org-level scheme
        org_level_count = Current.organization.payout_schemes.organization_level.count
        @payout_scheme.make_default! if org_level_count == 1

        notice = "Created #{@payout_scheme.name}. Customize it below."
        if (production = default_production_from_params)
          @payout_scheme.add_default_for_production!(production, effective_from: Date.current)
          notice = "Created #{@payout_scheme.name} and made it the default for #{production.name}. Customize it below."
        end

        redirect_to manage_edit_money_payout_scheme_path(@payout_scheme), notice: notice
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

    # The production a preset/new-scheme flow was started from, if it's one of
    # ours (never a bare Production.find on a URL param).
    def default_production_from_params
      return nil if params[:production_id].blank?

      Current.organization.productions.find_by(id: params[:production_id])
    end

    # Only an act-based production biases the flow toward per-act pay.
    def biased_production
      production = default_production_from_params
      production if production&.act_based?
    end

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

    # The form posts flat params (method, distribution[...], house_percentage,
    # expenses_first, individual_allocations, performer_overrides); the builder
    # owns the jsonb shape.
    def build_rules_from_params
      rules_params = params[:rules].respond_to?(:to_unsafe_h) ? params[:rules].to_unsafe_h : {}
      PayoutRulesBuilder.build(
        params.to_unsafe_h.slice("expenses_first", "house_percentage")
              .merge("method" => rules_params.dig("distribution", "method"))
              .merge(rules_params.slice("distribution", "individual_allocations", "performer_overrides"))
      )
    end
  end
end
