# frozen_string_literal: true

class AddGuestFieldsToShowPayoutLineItems < ActiveRecord::Migration[8.1]
  def change
    # Add guest-specific fields to track payments for guests
    add_column :show_payout_line_items, :is_guest, :boolean, default: false, null: false
    add_column :show_payout_line_items, :guest_name, :string
    add_column :show_payout_line_items, :guest_venmo, :string
    add_column :show_payout_line_items, :guest_zelle, :string

    # Make payee_id nullable for guest line items
    change_column_null :show_payout_line_items, :payee_id, true
  end
end
