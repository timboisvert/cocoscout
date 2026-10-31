# frozen_string_literal: true

# Seating (advanced ticketing plan §1, V1.4 step 4a): charts drawn for a
# room, their sections (rows, tables, standing areas) and seats; which
# seats a ticket type sells (zones); seats held off sale on a date; and a
# seat on a ticket, with the database refusing to sell one seat twice.
class CreateSeatCharts < ActiveRecord::Migration[8.1]
  def change
    create_table :seat_charts do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :location_space, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    create_table :seat_sections do |t|
      t.references :seat_chart, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "rows"
      t.integer :position, null: false, default: 0
      t.integer :standing_capacity, null: false, default: 0
      t.string :best_order, null: false, default: "center"
      t.integer :x, null: false, default: 0
      t.integer :y, null: false, default: 0
      t.integer :width, null: false, default: 0
      t.integer :height, null: false, default: 0
      t.timestamps
    end

    create_table :seats do |t|
      t.references :seat_section, null: false, foreign_key: true
      t.string :row_label, null: false
      t.integer :number, null: false
      t.string :label, null: false
      t.integer :x, null: false, default: 0
      t.integer :y, null: false, default: 0
      t.string :kind, null: false, default: "standard"
      t.string :note
      t.integer :best_rank, null: false, default: 0
      t.boolean :killed, null: false, default: false
      t.timestamps
    end
    add_index :seats, %i[seat_section_id row_label number], unique: true

    create_table :ticket_tier_zones do |t|
      t.references :ticket_tier, null: false, foreign_key: true
      t.references :seat_section, null: false, foreign_key: true
      t.timestamps
    end
    add_index :ticket_tier_zones, %i[ticket_tier_id seat_section_id], unique: true

    create_table :ticket_seat_holds do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "house"
      t.datetime :release_at
      t.string :owner_type
      t.bigint :owner_id
      t.datetime :released_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :ticket_seat_holds, %i[owner_type owner_id]

    create_table :ticket_seat_hold_seats do |t|
      t.references :ticket_seat_hold, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.references :seat, null: false, foreign_key: true
      t.timestamps
    end
    add_index :ticket_seat_hold_seats, %i[ticket_listing_id seat_id], unique: true

    add_reference :tickets, :seat, foreign_key: true
    add_reference :tickets, :seat_section, foreign_key: true
    add_index :tickets, %i[ticket_listing_id seat_id], unique: true, where: "seat_id IS NOT NULL AND status IN ('reserved', 'valid', 'checked_in')",
              name: "index_tickets_one_live_ticket_per_seat"

    add_column :production_ticketings, :seating_mode, :string
    add_reference :production_ticketings, :seat_chart, foreign_key: true
    add_column :ticket_listings, :seating_mode, :string
    add_reference :ticket_listings, :seat_chart, foreign_key: true
  end
end
