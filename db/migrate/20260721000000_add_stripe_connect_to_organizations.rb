# frozen_string_literal: true

# Stripe Connect Express account state for organizations, so an org can receive
# its own money (e.g. the leftover course revenue CocoScout holds) to its bank —
# the same rail performers and contractors are paid on. Mirrors the payee columns
# added in AddStripeConnectToPayees.
class AddStripeConnectToOrganizations < ActiveRecord::Migration[8.1]
  def change
    change_table :organizations, bulk: true do |t|
      t.string   :stripe_account_id
      t.string   :stripe_account_status
      t.boolean  :payouts_enabled, null: false, default: false
      t.datetime :stripe_account_synced_at
    end
    add_index :organizations, :stripe_account_id, unique: true, where: "stripe_account_id IS NOT NULL"
  end
end
