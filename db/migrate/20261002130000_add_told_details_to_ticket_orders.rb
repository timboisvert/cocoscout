# frozen_string_literal: true

# What each buyer was told about their show: its date, time and place when
# they bought, or when the theater last emailed them a change. When a show
# moves after people bought, the orders told something else are the ones
# its page asks the theater to tell (TicketShowChange).
class AddToldDetailsToTicketOrders < ActiveRecord::Migration[8.1]
  def up
    add_column :ticket_orders, :told_starts_at, :datetime
    add_column :ticket_orders, :told_location_id, :bigint
    add_column :ticket_orders, :told_location_space_id, :bigint

    # Everyone so far was told what the show says now.
    execute <<~SQL.squish
      UPDATE ticket_orders
      SET told_starts_at = shows.date_and_time, told_location_id = shows.location_id,
          told_location_space_id = shows.location_space_id
      FROM ticket_listings JOIN shows ON shows.id = ticket_listings.show_id
      WHERE ticket_listings.id = ticket_orders.ticket_listing_id
    SQL
  end

  def down
    remove_column :ticket_orders, :told_location_space_id
    remove_column :ticket_orders, :told_location_id
    remove_column :ticket_orders, :told_starts_at
  end
end
