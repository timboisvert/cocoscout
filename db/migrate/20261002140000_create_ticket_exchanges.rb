# frozen_string_literal: true

# Tickets moved to another date of the same production (TicketOrderExchange).
# The new order points back at the one its tickets came from; each move
# records the tickets, the money that went with them, and a cheaper date's
# refunded difference.
class CreateTicketExchanges < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_exchanges do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :from_order, null: false, foreign_key: { to_table: :ticket_orders }
      t.references :to_order, null: false, foreign_key: { to_table: :ticket_orders }, index: { unique: true }
      t.references :exchanged_by, foreign_key: { to_table: :users }
      t.references :ticket_refund, foreign_key: true
      t.jsonb :ticket_ids, null: false, default: []
      t.integer :moved_cents, null: false, default: 0
      t.integer :face_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :fees_cents, null: false, default: 0
      t.integer :difference_cents, null: false, default: 0
      t.timestamps
    end

    add_reference :ticket_orders, :exchanged_from, foreign_key: { to_table: :ticket_orders }
  end
end
