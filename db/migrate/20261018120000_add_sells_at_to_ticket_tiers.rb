# frozen_string_literal: true

# Where a ticket type sells (Tim, 2026-10-18, Burlioke's "$15 online, $20 at
# the door"): online and at the door, online only, or at the door only.
class AddSellsAtToTicketTiers < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_tiers, :sells_at, :string, null: false, default: "everywhere"
  end
end
