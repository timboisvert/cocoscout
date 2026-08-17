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
      @default_productions = @defaults.map(&:production).compact.uniq.sort_by { |production| production.name.to_s.downcase }
      @default_production_ids = @default_productions.map(&:id)
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

      # Productions that used it are left with no calculation — the picker on
      # their payouts page says so.
      productions = Current.organization.productions.where(id: @payout_scheme.payout_scheme_defaults.select(:production_id)).to_a
      @payout_scheme.destroy!
      productions.each { |production| ShowPayout.restamp_pending_for_production!(production, nil) }

      redirect_to manage_money_payout_calculations_path,
                  notice: "Payout calculation deleted."
    end

    # "Used by" — which productions pay their performers with this calculation.
    # Newly checked productions get it as their calculation from now on;
    # unchecked ones it used to cover lose only THIS calculation's rows (any
    # other calculation's history stays). Payouts nobody has calculated yet
    # follow the change (the model helpers restamp them).
    def update_defaults
      # Only this org's productions — ids come straight from the form.
      wanted_ids = Array(params[:production_ids]).map(&:to_i).reject(&:zero?)
      checked = Current.organization.productions.where(id: wanted_ids).to_a

      previously_covered = Current.organization.productions
                                  .where(id: @payout_scheme.payout_scheme_defaults.select(:production_id))
                                  .to_a
      checked_ids = checked.map(&:id)
      dropped = previously_covered.reject { |production| checked_ids.include?(production.id) }
      already = previously_covered.map(&:id)

      PayoutScheme.transaction do
        # Already-covered productions keep their row (and its start date).
        checked.reject { |production| already.include?(production.id) }
               .each { |production| @payout_scheme.make_production_scheme!(production) }
        dropped.each { |production| @payout_scheme.stop_covering!(production) }
      end

      redirect_to manage_money_payout_calculation_path(@payout_scheme),
                  notice: used_by_notice(checked)
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

    def used_by_notice(checked)
      if checked.any?
        "#{@payout_scheme.name} is now used by #{checked.map(&:name).sort.to_sentence}."
      else
        "#{@payout_scheme.name} isn't used by any production."
      end
    end
  end
end
