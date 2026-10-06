# frozen_string_literal: true

# A bundle is "4 × General for $70": it admits several people of another
# ticket type, using that type's seats. Each ticket it makes is that type's
# ticket, remembering the bundle it came from.
class BundlesAdmitATicketType < ActiveRecord::Migration[8.1]
  def change
    add_reference :ticket_tiers, :bundle_of_tier, foreign_key: { to_table: :ticket_tiers }, index: true
    add_reference :tickets, :bundle_tier, foreign_key: { to_table: :ticket_tiers }, index: true
  end
end
