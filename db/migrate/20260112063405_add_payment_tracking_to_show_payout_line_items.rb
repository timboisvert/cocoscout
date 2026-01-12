# frozen_string_literal: true

class AddPaymentTrackingToShowPayoutLineItems < ActiveRecord::Migration[8.1]
  def change
    # Payment method: stripe, cash, venmo, zelle, check, other, historical
    add_column :show_payout_line_items, :payment_method, :string
    add_column :show_payout_line_items, :payment_notes, :text
    add_column :show_payout_line_items, :stripe_transfer_id, :string
    add_column :show_payout_line_items, :paid_at, :datetime

    add_index :show_payout_line_items, :stripe_transfer_id, unique: true, where: "stripe_transfer_id IS NOT NULL"
    add_index :show_payout_line_items, :payment_method
  end
end
