# frozen_string_literal: true

# Per-organization virtual cash ledger over the single shared Stripe platform
# balance. Every dollar CocoScout holds is attributed to exactly one org (or,
# by omission, to CocoScout itself), so one org can never pay out another
# org's money even though it all sits in one Stripe account.
class CreateOrgCashEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :org_cash_entries do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :entry_type, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.string :description
      t.string :source_type
      t.bigint :source_id
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :org_cash_entries, %i[organization_id entry_type]
    add_index :org_cash_entries, %i[source_type source_id entry_type],
              unique: true, where: "source_id IS NOT NULL",
              name: "index_org_cash_entries_on_source_and_type"
  end
end
