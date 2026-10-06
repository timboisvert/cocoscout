# frozen_string_literal: true

# Tickets sold on other sites (Ticket Tailor, Eventbrite), by ticket type and
# site (Tim, 2026-10-06: "ten VIP front row is different than ten general
# admission"). Each type's seats shrink by its own count, always, so the
# reduce-or-not switch goes. Their sums feed the show's financials rows.
class CreateTicketOutsideSales < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_outside_sales do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.references :ticket_tier, null: false, foreign_key: true
      t.references :ticket_source, null: false, foreign_key: true
      t.integer :tickets_sold, null: false, default: 0
      t.integer :amount_cents, null: false, default: 0
      t.timestamps
    end
    add_index :ticket_outside_sales, %i[ticket_listing_id ticket_tier_id ticket_source_id], unique: true, name: "index_ticket_outside_sales_unique"
    remove_column :ticket_listings, :outside_sales_reduce_seats, :boolean, default: true, null: false
  end
end
