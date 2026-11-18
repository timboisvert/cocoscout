# frozen_string_literal: true

# How prices are shown ("all in", or before taxes and fees) was the box
# office's alone. A production and a date can each say otherwise now (nil
# follows the one above), so a production's Fees and taxes tab is the box
# office's with the ability to override (Tim, 2026-11-13).
class ProductionsAndDatesCanChooseHowPricesShow < ActiveRecord::Migration[8.1]
  def change
    add_column :production_ticketings, :price_display, :string
    add_column :ticket_listings, :price_display, :string
  end
end
