# frozen_string_literal: true

# A payout batch pays many payees at once through Stripe Connect. The org funds
# the total; each item is transferred to a payee's connected account and posts a
# `payout` ledger entry that debits their balance.
class CreatePayoutBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :payout_batches do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string   :trigger, null: false, default: "manual"   # manual | scheduled
      t.string   :status, null: false, default: "draft"     # draft/funding/funded/processing/completed/failed/canceled
      t.bigint   :total_cents, null: false, default: 0
      t.string   :funding_payment_intent_id
      t.string   :funding_status
      t.datetime :completed_at
      t.timestamps
    end

    create_table :payout_batch_items do |t|
      t.references :payout_batch, null: false, foreign_key: true
      t.string   :payee_type, null: false
      t.bigint   :payee_id, null: false
      t.bigint   :amount_cents, null: false
      t.string   :status, null: false, default: "pending"   # pending | paid | failed
      t.string   :stripe_transfer_id
      t.text     :error
      t.datetime :paid_at
      t.timestamps

      t.index [ :payee_type, :payee_id ]
    end
  end
end
