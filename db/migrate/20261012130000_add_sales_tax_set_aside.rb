# frozen_string_literal: true

# Sales tax kept out of what payout runs and withdrawals can spend (Tim,
# 2026-10-12: "set aside by default"). On from the day an organization is
# created, or from today for every organization already here, so tax
# collected (and maybe spent) before this never suddenly goes missing from
# a balance. A remittance is a period the organization has paid the
# government for one tax; its tax stops being set aside.
class AddSalesTaxSetAside < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :sales_tax_set_aside_since, :date, default: -> { "CURRENT_DATE" }

    create_table :sales_tax_remittances do |t|
      t.references :organization, null: false, foreign_key: true, index: false
      t.string :tax_name, null: false
      t.integer :rate_bps, null: false
      t.string :basis, null: false, default: "sale"
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.integer :amount_cents, null: false, default: 0
      t.date :paid_on, null: false
      t.string :reference
      t.references :recorded_by, foreign_key: { to_table: :users }, index: false
      t.timestamps
    end
    add_index :sales_tax_remittances, %i[organization_id tax_name rate_bps period_start], name: "idx_sales_tax_remittances_lookup"
  end
end
