# frozen_string_literal: true

# Which offline/"other" ways an org reports paying people outside CocoScout's
# Stripe rail (cash, check, Zelle, Venmo, other). Empty by default — Stripe is the
# norm; an org opts in per method under Money settings. Mirrors the existing
# jsonb list column default_contract_payment_methods.
class AddEnabledOfflinePayoutMethodsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :enabled_offline_payout_methods, :jsonb, default: [], null: false
  end
end
