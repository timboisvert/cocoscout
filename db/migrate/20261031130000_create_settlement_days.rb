# frozen_string_literal: true

# Settle up by day (Books V1.3, plan §9.2): one worksheet per day that had
# money in it, marked settled when every piece is checked. Which day a time
# belongs to follows the organization's setting (§9.6): smart days run from
# the morning until things stop; calendar days end at midnight.
class CreateSettlementDays < ActiveRecord::Migration[8.0]
  def change
    create_table :settlement_days do |t|
      t.references :organization, null: false, foreign_key: true
      t.date :date, null: false
      t.string :status, null: false, default: "open"
      t.datetime :settled_at
      t.references :settled_by, foreign_key: { to_table: :users }
      t.datetime :reopened_at
      t.references :reopened_by, foreign_key: { to_table: :users }
      t.text :reopen_reason
      t.jsonb :door_cash, null: false, default: {}
      t.text :notes
      t.timestamps
    end
    add_index :settlement_days, %i[organization_id date], unique: true

    add_column :organizations, :settlement_day_mode, :string, null: false, default: "smart"
    add_column :organizations, :settlement_day_starts_at, :integer, null: false, default: 6
  end
end
