# frozen_string_literal: true

# One seat in a hold on one date. Unique on (date, seat): a seat is in at
# most one hold at a time.
class TicketSeatHoldSeat < ApplicationRecord
  belongs_to :ticket_seat_hold, inverse_of: :hold_seats
  belongs_to :ticket_listing
  belongs_to :seat

  validates :seat_id, uniqueness: { scope: :ticket_listing_id, message: "is already held on this date" }
end
