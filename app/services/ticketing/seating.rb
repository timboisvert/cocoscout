# frozen_string_literal: true

module Ticketing
  # The seats on one date (advanced ticketing plan §1): which are free, which
  # are sold, held or killed, and which ticket type sells each one. Inventory
  # asks it for counts; the buyer's and the manager's maps ask it for the
  # picture (payload). One query each for tickets and holds, so a 2,000-seat
  # room is cheap.
  class Seating
    attr_reader :listing, :chart

    def initialize(listing, at: Time.current, excluding: nil)
      @listing = listing
      @chart = listing.effective_seat_chart
      @at = at
      @excluding = Array(excluding).map(&:to_i).presence
    end

    def seated? = @chart.present? && listing.effective_seating_mode != "general"

    # Live seats, by id, with their section loaded.
    def seats
      @seats ||= @chart.seats.live.includes(:seat_section).index_by(&:id)
    end

    # seat id => the ticket on it (sold, or reserved on a hold still ticking).
    def tickets_by_seat
      @tickets_by_seat ||= begin
        rows = Ticket.where(ticket_listing_id: listing.id).where.not(seat_id: nil)
                     .where("tickets.status IN (?) OR (tickets.status = 'reserved' AND ticket_orders.status = 'pending' AND ticket_orders.expires_at > ?)", Ticket::SOLD_STATUSES, @at)
                     .joins(:ticket_order)
        rows = rows.where.not(id: @excluding) if @excluding
        rows.index_by(&:seat_id)
      end
    end

    # seat id => the hold keeping it off sale.
    def holds_by_seat
      @holds_by_seat ||= TicketSeatHoldSeat.joins(:ticket_seat_hold).merge(TicketSeatHold.live(@at)).where(ticket_listing_id: listing.id)
                                           .includes(:ticket_seat_hold).index_by(&:seat_id)
    end

    def taken?(seat_id) = tickets_by_seat.key?(seat_id) || holds_by_seat.key?(seat_id)

    # The live seats a ticket type sells, free right now, best first.
    def free_seats(tier)
      ids = tier.zone_sections.select(&:seated?).map(&:id)
      return [] if ids.empty?

      seats.values.select { |s| ids.include?(s.seat_section_id) && !taken?(s.id) }.sort_by(&:best_rank)
    end

    # Seats in the type's zone, free or not (its size is the zone's capacity).
    def zone_seats(tier)
      ids = tier.zone_sections.select(&:seated?).map(&:id)
      seats.values.select { |s| ids.include?(s.seat_section_id) }
    end

    # Standing room a type sells: the areas' capacity less the tickets on them.
    def standing_remaining(tier)
      areas = tier.zone_sections.select(&:standing?)
      return nil if areas.empty?

      areas.sum(&:standing_capacity) - standing_taken(areas.map(&:id))
    end

    def standing_taken(section_ids)
      rows = Ticket.where(ticket_listing_id: listing.id, seat_section_id: section_ids, seat_id: nil).joins(:ticket_order)
                   .where("tickets.status IN (?) OR (tickets.status = 'reserved' AND ticket_orders.status = 'pending' AND ticket_orders.expires_at > ?)", Ticket::SOLD_STATUSES, @at)
      rows = rows.where.not(id: @excluding) if @excluding
      rows.count
    end

    # Every seat and area the chart has, for sale here: capacity.
    def capacity
      seats.size + @chart.standing_capacity
    end

    # The whole picture for a map: sections with their seats, each seat's
    # status (free / sold / held / killed) and the type that sells it.
    # own: ticket ids to show as "yours" (a buyer's own hold, a manager's
    # selected order).
    def payload(tiers: nil, own: [])
      tiers ||= listing.ticket_tiers.active.reject(&:bundle?)
      tier_by_section = {}
      tiers.each { |t| t.zone_section_ids.each { |sid| tier_by_section[sid] ||= t } }
      own = own.to_set
      {
        width: SeatChart::WIDTH, height: @chart.height,
        sections: @chart.sections.map do |section|
          tier = tier_by_section[section.id]
          {
            id: section.id, name: section.name, kind: section.kind, x: section.x, y: section.y, width: section.width, height: section.height,
            tier_id: tier&.id, tier_name: tier&.name, price_cents: tier && TicketPricing.all_in_price_cents(listing, tier),
            standing_capacity: section.standing_capacity, standing_remaining: (section.standing? ? section.standing_capacity - standing_taken([ section.id ]) : nil),
            seats: section.standing? ? [] : section.seats.map { |seat| seat_payload(seat, own) }
          }
        end
      }
    end

    def seat_payload(seat, own)
      ticket = tickets_by_seat[seat.id]
      hold = holds_by_seat[seat.id]
      status = if seat.killed then "killed"
      elsif ticket && own.include?(ticket.id) then "mine"
      elsif ticket then "sold"
      elsif hold then "held"
      else "free"
      end
      { id: seat.id, label: seat.label, x: seat.x, y: seat.y, kind: seat.kind, status: status, note: seat.note,
        hold: hold && { id: hold.ticket_seat_hold_id, name: hold.ticket_seat_hold.name, kind: hold.ticket_seat_hold.kind },
        ticket_id: ticket&.id, order_id: ticket&.ticket_order_id }
    end
  end
end
