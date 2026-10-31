# frozen_string_literal: true

# Group sales (advanced ticketing plan §3, V1.4 step 3): a block of seats
# held for a school or company, invoiced on 1.3's invoices, turned into
# tickets when paid. Quantity holds are how a general-admission block stays
# out of the seats for sale (Ticketing::Inventory counts them as taken).
class CreateTicketGroupBookings < ActiveRecord::Migration[8.1]
  def up
    create_table :ticket_quantity_holds do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.references :ticket_tier, foreign_key: true
      t.integer :quantity, null: false, default: 0
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.datetime :released_at
      t.timestamps
    end
    add_index :ticket_quantity_holds, %i[owner_type owner_id]
    add_index :ticket_quantity_holds, %i[ticket_listing_id released_at]

    create_table :ticket_group_bookings do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.references :ticket_tier, null: false, foreign_key: true
      t.references :invoice, foreign_key: true
      t.references :ticket_order, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :contact_name, null: false
      t.string :contact_email, null: false
      t.string :contact_phone
      t.integer :seat_count, null: false, default: 0
      t.integer :comp_count, null: false, default: 0
      t.integer :price_cents, null: false, default: 0
      t.date :due_on, null: false
      t.date :release_on, null: false
      t.text :notes
      t.text :names
      t.string :status, null: false, default: "booked"
      t.string :token, null: false
      t.datetime :ticketed_at
      t.datetime :released_at
      t.datetime :warned_at
      t.timestamps
    end
    add_index :ticket_group_bookings, :token, unique: true
    add_index :ticket_group_bookings, %i[organization_id status]

    TicketingTemplates.ensure!(keys: %w[ticket_group_booked ticket_group_tickets_ready ticket_group_release_warning ticket_group_released])
  end

  def down
    drop_table :ticket_group_bookings
    drop_table :ticket_quantity_holds
  end
end
