class AddSeatingZoneToTicketTiers < ActiveRecord::Migration[8.1]
  def change
    add_reference :ticket_tiers, :seating_zone, null: true, foreign_key: true
  end
end
