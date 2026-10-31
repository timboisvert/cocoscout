# frozen_string_literal: true

# One flip of a ticket type's price on one date, logged by
# TicketPriceChangeJob as a rule starts or stops matching.
class TicketPriceChange < ApplicationRecord
  belongs_to :organization
  belongs_to :ticket_listing
  belongs_to :ticket_tier
  belongs_to :ticket_price_rule, optional: true

  scope :recent, -> { order(created_at: :desc) }
end
