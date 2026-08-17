# frozen_string_literal: true

module Manage
  # Payout calculations — the PayoutScheme record, shown to users as a "payout
  # calculation". Creating and editing happens in PayoutCalculationWizardController;
  # this controller lists them, shows one, archives, and sets which productions
  # use one.
  class PayoutCalculationsController < Manage::ManageController
    before_action :set_payout_scheme, only: [ :show, :destroy, :update_defaults, :archive, :unarchive ]

    def index
      @show_archived = params[:archived] == "1"
      @payout_schemes = Current.organization.payout_schemes
                                            .then { |calculations| @show_archived ? calculations.archived : calculations.active }
                                            .order(:name)
                                            .includes(payout_scheme_defaults: :production)
      @archived_count = Current.organization.payout_schemes.archived.count
    end

    def show
      @show_payouts = @payout_scheme.show_payouts.includes(:show).order("shows.date_and_time DESC").limit(10)
      @defaults = @payout_scheme.payout_scheme_defaults.includes(:production).to_a
      @default_productions = @defaults.map(&:production).compact.sort_by { |production| production.name.to_s.downcase }
      @org_default = @defaults.any? { |default| default.production_id.nil? }
      # The modal offers every active production, plus any inactive one this
      # calculation still covers (so it can be unticked rather than vanish).
      @pickable_productions = (Current.organization.productions.active.to_a + @default_productions)
                                .uniq.sort_by { |production| production.name.to_s.downcase }
    end

    def destroy
      if @payout_scheme.show_payouts.paid.any?
        redirect_to manage_money_payout_calculations_path,
                    alert: "This calculation has paid people — archive it instead of deleting it."
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

      redirect_to manage_money_payout_calculations_path,
                  notice: "Payout calculation deleted."
    end

    # "Used by" — which productions this calculation is the default for, plus
    # whether it's the organization default. Checked productions get it as
    # their production calculation; unchecked ones it used to cover fall back
    # to the organization default. Payouts nobody has calculated yet follow
    # the change (the model helpers restamp them).
    def update_defaults
      # Only this org's productions — ids come straight from the form.
      wanted_ids = Array(params[:production_ids]).map(&:to_i).reject(&:zero?)
      checked = Current.organization.productions.where(id: wanted_ids).to_a
      org_default_wanted = params[:org_level_fallback] == "1"

      previously_covered = Current.organization.productions
                                  .where(id: @payout_scheme.payout_scheme_defaults.where.not(production_id: nil).select(:production_id))
                                  .to_a
      checked_ids = checked.map(&:id)
      dropped = previously_covered.reject { |production| checked_ids.include?(production.id) }
      already = previously_covered.map(&:id)

      org_default_changed = false
      PayoutScheme.transaction do
        # Already-covered productions keep their row (and its start date).
        checked.reject { |production| already.include?(production.id) }
               .each { |production| @payout_scheme.make_production_scheme!(production) }
        dropped.each { |production| PayoutScheme.clear_production_scheme!(production) }

        if org_default_wanted && !@payout_scheme.org_level_default?
          PayoutSchemeDefault.org_level
                             .joins(:payout_scheme)
                             .where(payout_schemes: { organization_id: Current.organization.id })
                             .destroy_all
          @payout_scheme.payout_scheme_defaults.create!(production_id: nil, effective_from: nil)
          org_default_changed = true
        elsif !org_default_wanted && @payout_scheme.org_level_default?
          @payout_scheme.payout_scheme_defaults.org_level.destroy_all
          org_default_changed = true
        end
      end

      # Productions without one of their own follow the organization default,
      # so their pending payouts need a fresh look too.
      if org_default_changed
        Current.organization.productions.find_each { |production| ShowPayout.restamp_pending_for_production!(production, nil) }
      end

      redirect_to manage_money_payout_calculation_path(@payout_scheme),
                  notice: used_by_notice(checked, org_default_wanted)
    end

    def archive
      @payout_scheme.archive!
      redirect_to manage_money_payout_calculations_path,
                  notice: "#{@payout_scheme.name} has been archived."
    end

    def unarchive
      @payout_scheme.unarchive!
      redirect_to manage_money_payout_calculation_path(@payout_scheme),
                  notice: "#{@payout_scheme.name} has been restored."
    end

    private

    def set_payout_scheme
      @payout_scheme = PayoutScheme.where(organization: Current.organization)
                                   .find(params[:id])
    end

    def used_by_notice(checked, org_default_wanted)
      parts = []
      parts << "the default for #{checked.map(&:name).sort.to_sentence}" if checked.any?
      parts << "the organization default" if org_default_wanted
      if parts.any?
        "#{@payout_scheme.name} is now #{parts.to_sentence}."
      else
        "#{@payout_scheme.name} is no longer the default for any production."
      end
    end
  end
end
