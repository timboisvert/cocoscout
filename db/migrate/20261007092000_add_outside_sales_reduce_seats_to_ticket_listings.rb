# frozen_string_literal: true

# Tickets sold on other sites (Ticket Tailor, Eventbrite) are typed on a
# show's ticketing page into the same Show Financials rows the worksheet
# uses. This switch says whether those seats come out of what CocoScout
# sells (Tim, 2026-10-06). On by default: listing a show in two places is
# the reason to type them.
class AddOutsideSalesReduceSeatsToTicketListings < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_listings, :outside_sales_reduce_seats, :boolean, default: true, null: false
  end
end
