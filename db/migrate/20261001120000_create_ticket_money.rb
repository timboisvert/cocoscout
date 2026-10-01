# frozen_string_literal: true

# The theater's CocoScout balance from ticket money: refunds drawn from it,
# withdrawals to the theater's bank, and how much of it a payout run spent
# instead of debiting the bank.
class CreateTicketMoney < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_refunds do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_order, null: false, foreign_key: true
      t.references :refunded_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.jsonb :ticket_ids, null: false, default: []
      t.boolean :keep_fees, null: false, default: false
      # What the buyer gets back, and where it came from.
      t.integer :amount_cents, null: false, default: 0
      t.integer :face_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :fees_cents, null: false, default: 0
      # Our 50¢ per ticket, never kept on a refund, so the theater's balance
      # gives up that much less than the buyer gets back.
      t.integer :platform_fee_waived_cents, null: false, default: 0
      t.integer :org_debit_cents, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.string :reason
      t.string :stripe_refund_id
      t.string :error
      t.timestamps
    end

    create_table :balance_withdrawals do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :amount_cents, null: false
      t.string :status, null: false, default: "pending"
      t.boolean :automatic, null: false, default: false
      t.string :stripe_transfer_id
      t.string :error
      t.timestamps
    end

    add_column :payout_batches, :balance_applied_cents, :integer, null: false, default: 0
    add_column :ticketing_profiles, :auto_withdraw, :string, null: false, default: "off"
  end
end
