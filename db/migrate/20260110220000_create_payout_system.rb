# frozen_string_literal: true

class CreatePayoutSystem < ActiveRecord::Migration[8.0]
  def change
    # Remove payment fields from roles (moved to dedicated payout system)
    remove_column :roles, :payment_type, :string, default: "non_paying", null: false
    remove_column :roles, :payment_amount, :decimal, precision: 10, scale: 2
    remove_column :roles, :payment_rate, :decimal, precision: 10, scale: 2
    remove_column :roles, :payment_minimum, :decimal, precision: 10, scale: 2

    # PayoutScheme - Named rule sets for how to calculate payouts
    create_table :payout_schemes do |t|
      t.references :production, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.jsonb :rules, null: false, default: {}
      t.boolean :is_default, default: false

      t.timestamps
    end

    add_index :payout_schemes, [ :production_id, :is_default ]

    # ShowFinancials - Revenue/expense inputs for a show
    create_table :show_financials do |t|
      t.references :show, null: false, foreign_key: true, index: { unique: true }
      t.integer :ticket_count, default: 0
      t.decimal :ticket_revenue, precision: 10, scale: 2, default: 0
      t.decimal :other_revenue, precision: 10, scale: 2, default: 0
      t.decimal :expenses, precision: 10, scale: 2, default: 0
      t.text :notes

      t.timestamps
    end

    # ShowPayout - Calculated payout statement for a show
    create_table :show_payouts do |t|
      t.references :show, null: false, foreign_key: true, index: { unique: true }
      t.references :payout_scheme, foreign_key: true
      t.jsonb :override_rules  # Event-level rule overrides
      t.string :status, null: false, default: "draft"  # draft, approved, paid
      t.decimal :total_payout, precision: 10, scale: 2
      t.datetime :calculated_at
      t.datetime :approved_at
      t.references :approved_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :show_payouts, :status

    # ShowPayoutLineItem - Per-person payout record
    create_table :show_payout_line_items do |t|
      t.references :show_payout, null: false, foreign_key: true
      t.references :payee, polymorphic: true, null: false  # Person or Group
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :shares, precision: 10, scale: 2  # For share-based calculations
      t.jsonb :calculation_details, default: {}  # Full breakdown of calculation
      t.text :notes

      t.timestamps
    end

    add_index :show_payout_line_items, [ :show_payout_id, :payee_type, :payee_id ],
              unique: true, name: "idx_payout_line_items_unique_payee"
  end
end
