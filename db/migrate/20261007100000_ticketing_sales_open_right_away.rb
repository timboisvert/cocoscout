# frozen_string_literal: true

# A new ticketing setup sells each date as soon as it's listed (Tim,
# 2026-10-06: "the default for ticketing should be to make it available
# immediately"); "N days before each date" stays as the alternative. Existing
# setups keep what they chose.
class TicketingSalesOpenRightAway < ActiveRecord::Migration[8.1]
  def change
    change_column_default :production_ticketings, :schedule_mode, from: "relative", to: "immediate"
  end
end
