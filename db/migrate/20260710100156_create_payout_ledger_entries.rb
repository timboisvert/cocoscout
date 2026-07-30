# frozen_string_literal: true

# The payout ledger is the spine of the new payout system. A performer's
# company-wide balance with an organization is SUM(amount_cents) of their
# entries — derived, never cached. Earnings are positive; advances and payouts
# are negative. Idempotent posting is enforced by a partial unique index on
# (source_type, source_id, entry_type).
class CreatePayoutLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :payout_ledger_entries do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :payee_type, null: false
      t.bigint :payee_id, null: false
      t.string :entry_type, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.string :source_type
      t.bigint :source_id
      t.string :description
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    # Balance lookups: entries for one payee within one organization.
    add_index :payout_ledger_entries, [ :organization_id, :payee_type, :payee_id ],
              name: "index_payout_ledger_entries_on_org_and_payee"

    # Idempotency: a given source can post at most one entry of each type.
    # Partial so manual entries (no source) are unconstrained.
    add_index :payout_ledger_entries, [ :source_type, :source_id, :entry_type ],
              unique: true, where: "source_id IS NOT NULL",
              name: "index_payout_ledger_entries_on_source_and_type"
  end
end
