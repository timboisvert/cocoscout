# frozen_string_literal: true

module Ticketing
  # Moving a sold ticket to another seat on the same date (advanced
  # ticketing plan §1): the QR code stays, the buyer hears "Your seats
  # changed". Under the listing lock, the new seat free and in the ticket
  # type's zone.
  class SeatMoves
    class Error < StandardError; end

    def self.move!(ticket, seat, by: nil, email: true)
      listing = ticket.ticket_listing
      raise Error, "This ticket isn't live." unless ticket.status.in?(Ticket::SOLD_STATUSES)
      raise Error, "That seat isn't on this date's chart." unless seat && listing.effective_seat_chart && seat.seat_section.seat_chart_id == listing.effective_seat_chart.id
      raise Error, "#{ticket.ticket_tier.name} doesn't sell #{seat.full_label}." unless ticket.ticket_tier.zone_section_ids.include?(seat.seat_section_id)

      raise Error, "They're already in #{seat.full_label}." if ticket.seat_id == seat.id

      from = ticket.seat_label
      listing.with_lock do
        seating = Seating.new(listing, excluding: ticket.id)
        raise Error, "#{seat.full_label} is taken." if seating.taken?(seat.id) || seat.killed
        TicketSeatHoldSeat.where(ticket_listing_id: listing.id, seat_id: seat.id).delete_all
        ticket.update!(seat: seat, seat_section: seat.seat_section)
      end
      TicketOrderMailer.seats_changed(ticket.ticket_order, [ [ from, ticket.seat_label ] ], by: by).deliver_later if email && ticket.ticket_order.buyer_email.present?
      ticket
    end
  end
end
