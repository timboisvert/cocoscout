# frozen_string_literal: true

module Ticketing
  # The seats a buyer (or the box office) chose for the tickets about to be
  # made, handed down to Ticket#take_a_seat without every flow having to
  # carry them: wrap the ticket-making in `with`, and each new ticket on a
  # seated date takes the next chosen seat its type sells, or best available
  # when the chosen ones run out. Thread-local, so it lives exactly as long
  # as the block, inside the listing lock.
  class SeatPlan
    KEY = :cocoscout_seat_plan

    def self.with(seat_ids, accessible: false, upgrade: false)
      previous = Thread.current[KEY]
      Thread.current[KEY] = { seats: Array(seat_ids).map(&:to_i), accessible: accessible, upgrade: upgrade }
      yield
    ensure
      Thread.current[KEY] = previous
    end

    def self.current = Thread.current[KEY]

    # The next chosen seat this ticket type sells, taken off the plan.
    def self.take!(tier, seating)
      plan = current
      return nil unless plan && plan[:seats].any?

      allowed = plan[:upgrade] ? nil : tier.base_tier.zone_sections.select(&:seated?).map(&:id)
      id = plan[:seats].find { |sid| (seat = seating.seats[sid]) && (allowed.nil? || allowed.include?(seat.seat_section_id)) }
      return nil unless id

      plan[:seats].delete(id)
      seating.seats[id]
    end

    def self.accessible? = current ? current[:accessible] : false
  end
end
