# frozen_string_literal: true

# Tax CocoScout collects as a seller's agent (tickets now, courses next). The
# theater sets the rates; rules say which rates apply to what; every taxed
# unit gets permanent tax lines that snapshot the rate, so changing a rate
# never rewrites history and the filing report reads straight from the lines.
# Exempt sales get zero-tax lines too: tax returns ask for exempt receipts.
class CreateTaxTables < ActiveRecord::Migration[8.1]
  def change
    create_table :tax_rates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :receipt_label
      t.integer :rate_bps, null: false # 10.25% = 1025
      t.string :jurisdiction
      t.string :kind, null: false, default: "sales"
      t.boolean :applies_to_fees, null: false, default: false
      t.string :remitter, null: false, default: "organization"
      t.string :registration_number
      t.date :effective_from
      t.date :effective_to
      t.datetime :archived_at
      t.timestamps
    end

    create_table :tax_rules do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :money_kind, null: false # "tickets", "courses"
      # Where the rule applies: nil = the org's default for that money kind;
      # otherwise a Location, Production, TicketListing or TicketTier.
      t.string :scope_type
      t.bigint :scope_id
      t.string :mode, null: false, default: "added" # "added" on top, or "included" in the price
      t.boolean :exempt, null: false, default: false
      t.string :exemption_reason
      t.jsonb :tax_rate_ids, null: false, default: []
      t.timestamps
    end
    # One rule per place: the org default (no scope) and each scoped rule.
    add_index :tax_rules, %i[organization_id money_kind], unique: true, where: "scope_type IS NULL",
              name: "idx_tax_rules_one_default"
    add_index :tax_rules, %i[organization_id money_kind scope_type scope_id], unique: true,
              where: "scope_type IS NOT NULL", name: "idx_tax_rules_one_per_scope"

    create_table :tax_lines do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :taxable_type, null: false
      t.bigint :taxable_id, null: false
      t.references :tax_rate, foreign_key: true
      t.string :name, null: false
      t.integer :rate_bps, null: false, default: 0
      t.string :jurisdiction
      t.string :remitter, null: false, default: "organization"
      t.boolean :included, null: false, default: false
      t.boolean :exempt, null: false, default: false
      t.string :exemption_reason
      t.integer :base_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0 # negative on a refund's reversal line
      t.date :sale_date, null: false
      t.date :event_date
      t.references :reversal_of, foreign_key: { to_table: :tax_lines }
      t.timestamps
    end
    add_index :tax_lines, %i[taxable_type taxable_id]
    add_index :tax_lines, %i[organization_id sale_date]
    add_index :tax_lines, %i[organization_id event_date]
  end
end
