# frozen_string_literal: true

# CocoScout's own money, side by side with what it holds for theaters, and
# both checked against Stripe:
#
#   stripe_balance_transactions — every line of the platform Stripe
#                                 balance, imported, each matched to the
#                                 CocoScout record that caused it
#   cocoscout_ledger_entries    — what CocoScout itself earned and spent
#                                 (the theaters' share is org_cash_entries)
#   billing_invoices            — what Stripe billed each org for Pro and
#                                 usage, and whether it was paid
#   platform_reconciliations    — the daily check: Stripe's balance against
#                                 the two ledgers
class CocoscoutMoneyRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_balance_transactions do |t|
      t.string :stripe_id, null: false
      t.string :txn_type, null: false
      t.string :reporting_category
      t.bigint :amount_cents, null: false
      t.bigint :fee_cents, null: false, default: 0
      t.bigint :net_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.string :status
      t.datetime :occurred_at, null: false
      t.date :available_on
      t.string :source_id
      t.jsonb :refs, null: false, default: {}
      t.string :description
      t.references :organization, foreign_key: true
      t.references :matched, polymorphic: true
      t.string :category, null: false, default: "unknown"
      t.string :match_status, null: false, default: "unmatched"
      t.bigint :expected_cents
      t.text :note
      t.references :explained_by, foreign_key: { to_table: :users }
      t.datetime :explained_at
      t.timestamps
    end
    add_index :stripe_balance_transactions, :stripe_id, unique: true
    add_index :stripe_balance_transactions, :occurred_at
    add_index :stripe_balance_transactions, :source_id
    add_index :stripe_balance_transactions, :match_status

    create_table :cocoscout_ledger_entries do |t|
      t.string :entry_type, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.references :organization, foreign_key: true
      t.references :source, polymorphic: true
      t.datetime :occurred_at, null: false
      t.string :description
      t.timestamps
    end
    add_index :cocoscout_ledger_entries, %i[source_type source_id entry_type], unique: true, name: "index_cocoscout_ledger_entries_on_source_and_type"
    add_index :cocoscout_ledger_entries, :occurred_at
    add_index :cocoscout_ledger_entries, :entry_type

    create_table :billing_invoices do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :stripe_invoice_id, null: false
      t.string :stripe_subscription_id
      t.string :stripe_payment_intent_id
      t.string :number
      t.string :kind, null: false, default: "other"
      t.string :status, null: false
      t.datetime :period_start
      t.datetime :period_end
      t.bigint :amount_due_cents, null: false, default: 0
      t.bigint :amount_paid_cents, null: false, default: 0
      t.bigint :amount_remaining_cents, null: false, default: 0
      t.jsonb :lines, null: false, default: []
      t.string :hosted_invoice_url
      t.string :invoice_pdf_url
      t.datetime :finalized_at
      t.datetime :paid_at
      t.datetime :failed_at
      t.string :failure_message
      t.timestamps
    end
    add_index :billing_invoices, :stripe_invoice_id, unique: true
    add_index :billing_invoices, :stripe_payment_intent_id
    add_index :billing_invoices, %i[organization_id period_start]

    create_table :platform_reconciliations do |t|
      t.date :checked_on, null: false
      t.datetime :checked_at, null: false
      t.bigint :stripe_balance_cents
      t.bigint :imported_net_cents, null: false, default: 0
      t.bigint :held_for_orgs_cents, null: false, default: 0
      t.bigint :cocoscout_cents, null: false, default: 0
      t.bigint :difference_cents
      t.integer :unmatched_count, null: false, default: 0
      t.integer :mismatch_count, null: false, default: 0
      t.integer :failed_webhook_count, null: false, default: 0
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :platform_reconciliations, :checked_on, unique: true
  end
end
