# frozen_string_literal: true

# Pricing rules (advanced ticketing plan §7c, V1.4 step 5): rules a manager
# writes that move a ticket type's price as a date sells or draws near,
# within the type's floor and ceiling; every flip logged for the date page
# and Reports.
class CreateTicketPriceRules < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_price_rules do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :production_ticketing, null: false, foreign_key: true
      t.references :ticket_tier, foreign_key: true
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.string :name, null: false, default: ""
      t.string :condition, null: false
      t.integer :threshold, null: false, default: 0
      t.integer :days, null: false, default: 0
      t.string :change_kind, null: false
      t.integer :change_value, null: false, default: 0
      t.timestamps
    end

    create_table :ticket_price_changes do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.references :ticket_tier, null: false, foreign_key: true
      t.references :ticket_price_rule, foreign_key: true
      t.integer :from_cents, null: false
      t.integer :to_cents, null: false
      t.timestamps
    end

    add_column :ticket_tiers, :price_floor_cents, :integer
    add_column :ticket_tiers, :price_ceiling_cents, :integer
  end
end
