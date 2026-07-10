# frozen_string_literal: true

# Two-tier subscription system (Free + Pro). Organizations default to the free
# tier; Pro is either self-serve via Stripe or comped by a superadmin. See
# Organization#on_paid_plan? for the single access gate.
class AddSubscriptionToOrganizations < ActiveRecord::Migration[8.1]
  def change
    change_table :organizations, bulk: true do |t|
      t.string   :subscription_tier, null: false, default: "free"
      t.string   :stripe_customer_id
      t.string   :stripe_subscription_id
      t.string   :subscription_status
      t.string   :subscription_interval
      t.datetime :subscription_current_period_end
      t.datetime :subscription_canceled_at
      t.datetime :comped_until
      t.boolean  :comped_indefinitely, null: false, default: false
    end

    add_index :organizations, :stripe_customer_id
    add_index :organizations, :stripe_subscription_id
  end
end
