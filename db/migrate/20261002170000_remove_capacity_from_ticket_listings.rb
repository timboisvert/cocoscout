# frozen_string_literal: true

# A date's seats are its ticket types' seats; a separate "seats in the room"
# number was never set anywhere anymore (Tim, 2026-10-02).
class RemoveCapacityFromTicketListings < ActiveRecord::Migration[8.1]
  def change
    remove_column :ticket_listings, :capacity, :integer
  end
end
