# frozen_string_literal: true

# A deal on another show (Tim, 2026-10-05): "You're buying Boylesque; add
# tonight's Laugh Along Live for $5 off." Offered at checkout, and for a few
# days after a purchase. Deal tickets remember their deal; a checkout started
# from an earlier purchase's deal remembers that purchase.
class CreateTicketOffers < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_offers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      # When it's offered: buying a date (listing), any date of a production,
      # or anything the organization sells.
      t.string :trigger_scope, null: false, default: "production"
      t.references :trigger_listing, foreign_key: { to_table: :ticket_listings }
      t.references :trigger_production, foreign_key: { to_table: :productions }
      # What it offers: a date's ticket type, or the same night at a production.
      t.string :target_scope, null: false, default: "listing"
      t.references :target_tier, foreign_key: { to_table: :ticket_tiers }
      t.references :target_production, foreign_key: { to_table: :productions }
      t.string :target_tier_name
      # The deal: amount_off, percent_off or price.
      t.string :deal_kind, null: false, default: "amount_off"
      t.integer :amount_cents
      t.decimal :percent, precision: 5, scale: 2
      t.integer :price_cents
      # Up to as many as the tickets bought, unless a number is set.
      t.integer :max_per_order
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :active, null: false, default: true
      t.integer :max_uses
      t.integer :after_purchase_days, null: false, default: 2
      t.integer :shown_count, null: false, default: 0
      t.timestamps
    end

    add_reference :tickets, :ticket_offer, foreign_key: true
    add_reference :ticket_purchases, :earned_by_purchase, foreign_key: { to_table: :ticket_purchases }
  end
end
