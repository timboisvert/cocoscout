# frozen_string_literal: true

# What CocoScout costs to run that never passes through Stripe: Amazon,
# Claude, anything else Coco Runs Everything pays for it. Kept apart from
# cocoscout_ledger_entries, which has to match Stripe to the cent.
class CreateCompanyExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :company_expenses do |t|
      t.string :vendor, null: false
      t.string :category, null: false, default: "other"
      t.string :description
      t.string :bill_number
      t.bigint :bill_total_cents, null: false, default: 0
      t.decimal :share_percent, precision: 5, scale: 2, null: false, default: 100
      t.bigint :amount_cents, null: false, default: 0
      t.date :period_month
      t.date :billed_on
      t.date :paid_on
      t.string :paid_by, null: false, default: "company"
      t.jsonb :breakdown, null: false, default: []
      t.text :note
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :company_expenses, :period_month
    add_index :company_expenses, [ :vendor, :bill_number ], unique: true, where: "bill_number IS NOT NULL"
  end
end
