# frozen_string_literal: true

class ReplaceStripeWithVenmoForPayouts < ActiveRecord::Migration[8.1]
  def change
    # === PEOPLE TABLE ===
    # Remove Stripe fields
    remove_index :people, :stripe_account_id, if_exists: true
    remove_index :people, :stripe_account_status, if_exists: true
    remove_column :people, :stripe_account_id, :string
    remove_column :people, :stripe_account_status, :string
    remove_column :people, :stripe_payouts_enabled, :boolean
    remove_column :people, :stripe_details_submitted, :boolean
    remove_column :people, :stripe_onboarding_completed_at, :datetime

    # Add Venmo fields to people
    add_column :people, :venmo_identifier, :string
    add_column :people, :venmo_identifier_type, :string
    add_column :people, :venmo_verified_at, :datetime

    # === GROUPS TABLE ===
    # Add Venmo fields to groups (groups can also be payees)
    add_column :groups, :venmo_identifier, :string
    add_column :groups, :venmo_identifier_type, :string
    add_column :groups, :venmo_verified_at, :datetime

    # === SHOW_PAYOUT_LINE_ITEMS TABLE ===
    # Remove old Stripe index
    remove_index :show_payout_line_items, :stripe_transfer_id, if_exists: true

    # Rename stripe_transfer_id to payout_reference_id
    rename_column :show_payout_line_items, :stripe_transfer_id, :payout_reference_id

    # Add new PayPal/Venmo payout tracking fields
    add_column :show_payout_line_items, :paypal_batch_id, :string
    add_column :show_payout_line_items, :payout_status, :string
    add_column :show_payout_line_items, :payout_error, :text

    # Add indexes for the new fields
    add_index :show_payout_line_items, :payout_reference_id, unique: true, where: "payout_reference_id IS NOT NULL"
    add_index :show_payout_line_items, :paypal_batch_id
    add_index :show_payout_line_items, :payout_status
  end
end
