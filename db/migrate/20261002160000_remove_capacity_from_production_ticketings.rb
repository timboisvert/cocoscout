# frozen_string_literal: true

# A production's dates are limited by each ticket type's seats; a separate
# "seats in the room" number only got in the way (Tim, 2026-10-02).
class RemoveCapacityFromProductionTicketings < ActiveRecord::Migration[8.1]
  def change
    remove_column :production_ticketings, :capacity, :integer
  end
end
