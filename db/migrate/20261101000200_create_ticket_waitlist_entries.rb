# frozen_string_literal: true

# The waitlist (advanced ticketing plan §7b): people who want a sold-out
# date, offered returned seats in turn, by email. Each production switches
# its waitlist on in Settings → Sales.
class CreateTicketWaitlistEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_waitlist_entries do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.integer :quantity, null: false, default: 1
      t.string :preference, null: false, default: "any"
      t.integer :position, null: false, default: 0
      t.string :status, null: false, default: "waiting"
      t.datetime :offered_at
      t.datetime :offer_expires_at
      t.references :offer_order, foreign_key: { to_table: :ticket_orders }
      t.string :token, null: false
      t.timestamps
    end
    add_index :ticket_waitlist_entries, :token, unique: true
    add_index :ticket_waitlist_entries, %i[ticket_listing_id status position]
    add_index :ticket_waitlist_entries, %i[ticket_listing_id email], unique: true, where: "status IN ('waiting', 'offered')", name: "index_ticket_waitlist_entries_one_live_per_email"

    add_column :production_ticketings, :waitlist, :boolean, null: false, default: false
    # A waitlist offer holds its seats longer than a checkout's ten minutes.
    add_column :ticket_orders, :waitlist_offer, :boolean, null: false, default: false

    reversible do |dir|
      dir.up { TicketingTemplates.ensure!(keys: %w[ticket_waitlist_joined ticket_waitlist_offer ticket_waitlist_missed ticket_waitlist_note]) }
    end
  end
end
