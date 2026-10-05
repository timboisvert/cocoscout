# frozen_string_literal: true

# From how many seats left a ticket page says "Only N left": 5 unless the
# production (or one of its dates) says otherwise.
class AddLowStockThreshold < ActiveRecord::Migration[8.1]
  def change
    add_column :production_ticketings, :low_stock_threshold, :integer
    add_column :ticket_listings, :low_stock_threshold, :integer
  end
end
