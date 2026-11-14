# frozen_string_literal: true

# Whether cash at the door is priced like every other sale ("same", the
# default, so nothing changes for anyone) or holds its tax inside the price (Tim,
# 2026-11-13: nobody wants to make change in coins, so a $20 ticket is $20
# in cash, with the tax taken out of it). One box office setting; a
# production and a date can each say otherwise (nil follows the one above),
# as "who pays the fees" does.
class CashSalesCanHoldTheirTax < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :cash_tax, :string, default: "same", null: false
    add_column :production_ticketings, :cash_tax, :string
    add_column :ticket_listings, :cash_tax, :string
  end
end
