# frozen_string_literal: true

# One checkout, one payment, one order per show: a buyer can pay once for
# tickets to several shows (a pass, or a deal on another show). Each show
# keeps its own order, so the door, refunds and every show's money work as
# they did.
class CreateTicketPurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_purchases do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :token, null: false
      t.string :status, null: false, default: "pending"
      t.string :channel, null: false, default: "online"
      t.datetime :expires_at
      t.datetime :paid_at
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :platform_fee_cents, null: false, default: 0
      t.integer :processing_cents, null: false, default: 0
      t.integer :buyer_fee_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.integer :org_net_cents, null: false, default: 0
      t.string :stripe_payment_intent_id
      t.string :stripe_charge_id
      t.timestamps
    end
    add_index :ticket_purchases, :token, unique: true
    add_index :ticket_purchases, :stripe_payment_intent_id, unique: true, where: "stripe_payment_intent_id IS NOT NULL"
    add_index :ticket_purchases, :expires_at, where: "status = 'pending'"

    add_reference :ticket_orders, :ticket_purchase, foreign_key: true
  end
end
