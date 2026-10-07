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

  # A contracted night's times in words: the booking, and the show inside it
  # when it runs at its own time. "Fri, Oct 23 · 9:00 PM–11:30 PM · show 9:30 PM–11:00 PM"
  def night_times_words(starts_at:, ends_at:, event_starts_at: nil, event_ends_at: nil)
    words = "#{starts_at.strftime('%a, %b %-d')} · #{starts_at.strftime('%-l:%M %p')}–#{ends_at.strftime('%-l:%M %p')}"
    show_start = event_starts_at || starts_at
    show_end = event_ends_at || ends_at
    return words if show_start == starts_at && show_end == ends_at

    "#{words} · show #{show_start.strftime('%-l:%M %p')}–#{show_end.strftime('%-l:%M %p')}"
  end

  # Where "change the name or description" goes for this viewer.
  def where_to_change_production_basics(production)
    if can_amend_production_basics?(production)
      amend_basics_manage_contract_path(production_basics_contract(production))
    else
      edit_manage_production_path(production)
    end
  end
end
