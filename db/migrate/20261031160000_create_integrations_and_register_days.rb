# frozen_string_literal: true

# Integrations (Organization settings → Integrations) and what a register
# integration brings in (Books V1.3, plan §9.3): Square first. A RegisterDay
# is one location's business day, read by the day's Settle up worksheet;
# a RegisterPull is one line of the pull log; a TipShare is one person's
# share of a day's tips.
class CreateIntegrationsAndRegisterDays < ActiveRecord::Migration[8.0]
  def change
    create_table :integrations do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :status, null: false, default: "connected"
      t.text :credentials
      t.jsonb :settings, null: false, default: {}
      t.references :connected_by, foreign_key: { to_table: :users }
      t.datetime :connected_at
      t.datetime :last_synced_at
      t.text :last_error
      t.timestamps
    end
    add_index :integrations, %i[organization_id provider], unique: true

    create_table :register_days do |t|
      t.references :integration, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.references :location, foreign_key: true
      t.string :external_location_id, null: false
      t.date :business_date, null: false
      t.jsonb :sales_by_category, null: false, default: {}
      t.integer :gross_cents, null: false, default: 0
      t.integer :tips_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :refunds_cents, null: false, default: 0
      t.integer :fees_cents, null: false, default: 0
      t.integer :net_cents, null: false, default: 0
      t.integer :orders_count, null: false, default: 0
      t.datetime :pulled_at
      t.timestamps
    end
    add_index :register_days, %i[integration_id external_location_id business_date], unique: true, name: "index_register_days_on_location_and_date"
    add_index :register_days, %i[organization_id business_date]

    create_table :register_pulls do |t|
      t.references :integration, null: false, foreign_key: true
      t.string :trigger, null: false, default: "manual"
      t.string :status, null: false, default: "running"
      t.date :from_date, null: false
      t.date :to_date, null: false
      t.integer :orders_count, null: false, default: 0
      t.text :error
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps
    end

    create_table :tip_shares do |t|
      t.references :settlement_day, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.integer :amount_cents, null: false, default: 0
      t.string :method, null: false, default: "payout" # payout / cash
      t.references :payout_contribution, foreign_key: true
      t.timestamps
    end
    add_index :tip_shares, %i[settlement_day_id person_id], unique: true

    add_column :settlement_days, :register_checked_at, :datetime
    add_column :settlement_days, :tips_split, :string
    add_column :settlement_days, :tips_checked_at, :datetime
  end
end
