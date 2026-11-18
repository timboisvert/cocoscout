# frozen_string_literal: true

# While a contract is connected, the contractor's poster, wide image and
# description stand in on the selling organization's ticket pages for the
# show (LinkedArt). The selling organization can go back to its own.
class ConnectionsChooseWhoseImagesTheTicketPageShows < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_connections, :use_own_images, :boolean, null: false, default: false
  end
end
