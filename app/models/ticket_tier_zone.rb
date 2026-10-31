# frozen_string_literal: true

# A ticket type's zone on a chart, one section at a time: "Orchestra sells as
# Premium", "Balcony and Mezzanine sell as General". A ticket type with no
# zone on a seated date sells nothing there.
class TicketTierZone < ApplicationRecord
  belongs_to :ticket_tier
  belongs_to :seat_section

  validates :seat_section_id, uniqueness: { scope: :ticket_tier_id }
end
