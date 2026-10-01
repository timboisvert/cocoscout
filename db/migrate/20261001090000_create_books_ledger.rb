# frozen_string_literal: true

# The books: a real double-entry ledger under each organization's money,
# hidden behind CocoScout's plain money screens. Every money event posts one
# balanced, immutable journal entry; corrections are reversing entries, never
# edits. Ticketing is the first thing to post here; the rest of the money
# (payouts, courses, contracts, expenses) follows.
#
# Lines carry the production-economics dimensions (production, show, payee) so
# profit can still be sliced by show, plus a fund tag for nonprofits' restricted
# money (stored from day one; no funds table or screens yet). Dimensions are
# plain ids, not foreign keys: the books keep their history even when a show
# is deleted.
class CreateBooksLedger < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_accounts do |t|
      t.references :organization, null: false, foreign_key: true, index: false
      # Stable handle for the accounts every org gets ("ticket_income"); nil
      # for accounts a theater adds itself.
      t.string :key
      t.string :code, null: false
      t.string :name, null: false
      t.string :account_type, null: false
      t.string :subtype
      t.boolean :system, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :ledger_accounts, %i[organization_id code], unique: true
    add_index :ledger_accounts, %i[organization_id key], unique: true, where: "key IS NOT NULL"

    create_table :journal_entries do |t|
      t.references :organization, null: false, foreign_key: true, index: false
      t.string :source_type
      t.bigint :source_id
      # What the source posted ("sale", "recognition", "refund:42"): one live
      # entry per source and kind, so re-posting restates instead of doubling.
      t.string :kind, null: false
      t.date :entry_date, null: false # earned or incurred (accrual)
      t.date :cash_date               # money moved (cash basis); nil until it does
      t.string :memo
      t.datetime :posted_at, null: false
      t.datetime :reversed_at
      t.references :reversal_of, foreign_key: { to_table: :journal_entries }
      t.timestamps
    end
    add_index :journal_entries, %i[organization_id entry_date]
    add_index :journal_entries, %i[organization_id cash_date]
    add_index :journal_entries, %i[source_type source_id kind], unique: true,
              where: "reversed_at IS NULL AND reversal_of_id IS NULL",
              name: "idx_journal_entries_one_live_per_source_kind"

    create_table :journal_lines do |t|
      t.references :journal_entry, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true, index: false
      t.references :ledger_account, null: false, foreign_key: true
      t.bigint :amount_cents, null: false # debit +, credit −
      t.bigint :production_id
      t.bigint :show_id
      t.string :payee_type
      t.bigint :payee_id
      t.bigint :fund_id
      t.string :memo
      t.timestamps
    end
    add_index :journal_lines, %i[organization_id ledger_account_id]
    add_index :journal_lines, :production_id
    add_index :journal_lines, :show_id
    add_index :journal_lines, %i[payee_type payee_id]
    add_index :journal_lines, :fund_id
  end
end
