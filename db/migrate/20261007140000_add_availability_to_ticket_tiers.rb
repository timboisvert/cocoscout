# frozen_string_literal: true

# A date's own say over one ticket type (Tim, 2026-10-07): on sale, marked
# sold out (still shown, can't be bought), or hidden from the ticket page.
# Set per date and never copied down from the production's setup.
class AddAvailabilityToTicketTiers < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_tiers, :availability, :string, default: "on_sale", null: false
  end
end
