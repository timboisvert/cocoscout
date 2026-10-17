# frozen_string_literal: true

# A date's Codes tab on the follow-or-own pattern (Tim, 2026-10-17): off, the
# production's codes work on it; on, only its own do. A date that already
# had its own codes keeps using them.
class AddOwnCodesToTicketListings < ActiveRecord::Migration[8.1]
  def up
    add_column :ticket_listings, :own_codes, :boolean, null: false, default: false
    execute <<~SQL.squish
      UPDATE ticket_listings SET own_codes = TRUE
      WHERE id IN (SELECT ticket_listing_id FROM ticket_discount_codes WHERE ticket_listing_id IS NOT NULL AND active = TRUE)
    SQL
  end

  def down
    remove_column :ticket_listings, :own_codes
  end
end
