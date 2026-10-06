# frozen_string_literal: true

# Tickets one other site (Ticket Tailor, Eventbrite) sold for one show, of one
# ticket type: "10 VIP on Ticket Tailor". Typed on the show's ticketing page.
# Each type's seats here shrink by its count (Ticketing::Inventory), and a
# site's rows add up to its Show Financials line (TicketOutsideSales).
class TicketOutsideSale < ApplicationRecord
  belongs_to :organization
  belongs_to :ticket_listing
  belongs_to :ticket_tier
  belongs_to :ticket_source

  validates :tickets_sold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
