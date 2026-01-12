# frozen_string_literal: true

class AddStripeFieldsToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :stripe_account_id, :string
    add_column :people, :stripe_account_status, :string, default: "not_connected"
    add_column :people, :stripe_onboarding_completed_at, :datetime
    add_column :people, :stripe_payouts_enabled, :boolean, default: false
    add_column :people, :stripe_details_submitted, :boolean, default: false

    add_index :people, :stripe_account_id, unique: true, where: "stripe_account_id IS NOT NULL"
    add_index :people, :stripe_account_status
  end
end
