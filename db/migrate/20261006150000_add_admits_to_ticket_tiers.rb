# frozen_string_literal: true

# A ticket type can admit more than one person: "4 tickets for $70" admits 4.
# Each one bought becomes that many tickets (one per person), splitting the
# price, and takes that many seats.
class AddAdmitsToTicketTiers < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_tiers, :admits, :integer, null: false, default: 1
  end
end
