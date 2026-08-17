# frozen_string_literal: true

module PayoutHelper
  # Should this production be nudged to set up per-act pay? Only when it casts
  # by acts, the org can pay performers at all (Pro), and nobody has picked a
  # payout calculation for it yet.
  def production_needs_per_act_calculation_nudge?(production)
    return false unless production&.act_based?
    return false unless production.organization&.feature_available?(:money)

    PayoutScheme.current_default_for_production(production).nil?
  end
end
