# frozen_string_literal: true

# Stripe Connect Express account state for payees (people and contractors), so
# they can receive real bank payouts. Groups/guests can't hold a Connect account.
class AddStripeConnectToPayees < ActiveRecord::Migration[8.1]
  def change
    %i[people contractors].each do |table|
      change_table table, bulk: true do |t|
        t.string   :stripe_account_id
        t.string   :stripe_account_status
        t.boolean  :payouts_enabled, null: false, default: false
        t.datetime :stripe_account_synced_at
      end
      add_index table, :stripe_account_id, unique: true, where: "stripe_account_id IS NOT NULL"
    end
  end
end
