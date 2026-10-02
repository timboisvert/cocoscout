# frozen_string_literal: true

# Ticketing set up once, on a production, the way sign-ups handle repeating
# events: which of its events are included (all its performances, some event
# types, or dates picked by hand), when each one's sales open (as soon as
# it's listed, or N days before it) and close, its ticket types and prices,
# fees, page words and notes. Every included show gets a listing from this
# setup, and each show can still change its own (a listing's blank field
# means "the production's"). The production's ticket types are copied onto
# each show and kept in sync while the show inherits them.
class CreateProductionTicketings < ActiveRecord::Migration[8.1]
  def change
    create_table :production_ticketings do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :event_matching, null: false, default: "all"
      t.jsonb :event_type_filter, null: false, default: []
      t.string :schedule_mode, null: false, default: "relative"
      t.integer :opens_days_before, null: false, default: 30
      t.integer :online_close_minutes, null: false, default: 0
      t.string :fee_mode
      t.integer :max_per_order
      t.integer :capacity
      t.string :title
      t.text :description
      t.string :door_note
      t.string :age_note
      t.string :accessibility_note
      t.timestamps
    end

    # The dates picked by hand, when event_matching is "manual".
    create_table :production_ticketing_shows do |t|
      t.references :production_ticketing, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.timestamps
    end
    add_index :production_ticketing_shows, %i[production_ticketing_id show_id], unique: true, name: "index_production_ticketing_shows_once"

    change_column_null :ticket_tiers, :ticket_listing_id, true
    add_reference :ticket_tiers, :production_ticketing, foreign_key: true
    add_reference :ticket_tiers, :source_tier, foreign_key: { to_table: :ticket_tiers }
    add_column :ticket_listings, :inherits_tiers, :boolean, null: false, default: false
  end
end
