# frozen_string_literal: true

module ManageHelper
  # A contracted production's name and description belong to its running
  # contract (Amend → Change the basic info), so the contract and the
  # production never disagree. Nil when the production edit page owns them:
  # an in-house production, a contract that's finished, or a plan without
  # Contracts.
  def production_basics_contract(production)
    return nil unless production.organization.feature_available?(:contracts)

    production.basics_contract
  end

  # Contracts are the organization's managers' (PaidFeatureGate), so only they
  # get the way in.
  def can_amend_production_basics?(production)
    return false unless production_basics_contract(production)

    Current.user&.superadmin? || production.organization.manageable_by?(Current.user)
  end

  # Where "change the name or description" goes for this viewer.
  def production_basics_path(production)
    if can_amend_production_basics?(production)
      amend_basics_manage_contract_path(production_basics_contract(production))
    else
      edit_manage_production_path(production)
    end
  end
end
