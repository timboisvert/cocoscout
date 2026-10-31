# frozen_string_literal: true

module Ticketing
  # The only code that answers "how many seats are left?" for a listing.
  #
  # A seat is taken by a sold ticket (valid or checked in), and by a reserved
  # one while its order is still holding it — wherever the ticket was sold.
  # Tickets sold on other sites (Ticket Tailor, Eventbrite) are the counts the
  # theater types on the show's page, per ticket type (TicketOutsideSale);
  # they take that type's seats here, so a show listed in two places never
  # oversells. Nothing else in the app counts tickets.
  #
  # Capacity is the sum of the tiers' seats when every tier has a count; nil
  # means no limit. A tier's own seats cap it too.
  class Inventory
    class SoldOut < StandardError; end

    # excluding: tickets that are giving up their seats in the same breath
    # (a move to another ticket type on the same date), so they don't count
    # against the seats they're moving into.
    def initialize(listing, at: Time.current, excluding: nil)
      @listing = listing
      @at = at
      @excluding = Array(excluding).map(&:to_i).presence
    end

    # Sold by the seat (advanced ticketing §1): counts come from the chart.
    def seated? = @listing.seated?

    def seating
      @seating ||= Seating.new(@listing, at: @at, excluding: @excluding)
    end

    # The seats on sale: the ticket types' seats added up, when every type
    # has a count; else the room's "most people allowed" (advanced ticketing
    # plan §0: the production's own counts win over the room's); else no
    # limit.
    def capacity
      return seating.capacity if seated?

      # A bundle has no seats of its own: it uses its type's.
      tiers = @listing.ticket_tiers.active.reject(&:bundle?)
      return tiers.sum(&:quantity) if tiers.any? && tiers.all?(&:quantity)

      room = @listing.show.location_space
      room.capacity if room&.capacity.to_i.positive?
    end

    def sold(tier: nil)
      scope(tier).where(status: Ticket::SOLD_STATUSES).count
    end

    def held(tier: nil)
      scope(tier).where(status: "reserved").joins(:ticket_order).merge(TicketOrder.holding(@at)).count
    end

    # Seats sold on other sites, by the ticket type the theater said (Tim,
    # 2026-10-06: "ten VIP on Ticket Tailor" comes off VIP's seats). For the
    # whole show, every type added up. A bundle's are its type's.
    def outside(tier: nil)
      tier = tier.base_tier if tier&.bundle?
      tier ? outside_by_tier.fetch(tier.id, 0) : outside_by_tier.values.sum
    end

    def outside_sold
      outside
    end

    def outside_by_tier
      @outside_by_tier ||= TicketOutsideSale.where(ticket_listing_id: @listing.id).group(:ticket_tier_id).sum(:tickets_sold)
    end

    # "10 on Ticket Tailor and 2 on Eventbrite", for one type or the show.
    def outside_words(tier: nil)
      outside_lines(tier: tier).to_sentence
    end

    # The same, one site a line: ["10 on Ticket Tailor", "2 on Eventbrite"].
    def outside_lines(tier: nil)
      outside_by_site(tier: tier).select { |_, n, _| n.positive? }.map { |name, n, _| "#{n} on #{name}" }
    end

    # Each other site's tickets and money, most tickets first:
    # [["HotTix", 5, 45_000], ["Ticket Tailor", 3, 2_700]].
    def outside_by_site(tier: nil)
      outside_rows(tier).joins(:ticket_source).group("ticket_sources.name").pluck("ticket_sources.name", Arel.sql("SUM(tickets_sold)"), Arel.sql("SUM(amount_cents)"))
                        .map { |name, n, cents| [ name, n.to_i, cents.to_i ] }.reject { |_, n, cents| n.zero? && cents.zero? }
                        .sort_by { |name, n, cents| [ -n, -cents, name ] }
    end

    # The money other sites took, as typed on the show's page, by site:
    # [["HotTix", 45_000], ["Ticket Tailor", 2_700]], biggest first, only
    # sites with an amount. Not CocoScout's money: never in the balance.
    def outside_amounts(tier: nil)
      outside_rows(tier).joins(:ticket_source).group("ticket_sources.name").sum(:amount_cents)
                        .select { |_, cents| cents.positive? }.sort_by { |name, cents| [ -cents, name ] }
    end

    def outside_cents(tier: nil)
      outside_rows(tier).sum(:amount_cents)
    end

    # Seats kept out of sale for someone (TicketQuantityHold: a group's
    # block). A hold on a type counts against that type; a hold on the date
    # as a whole counts against the date only.
    def blocked(tier: nil)
      tier = tier.base_tier if tier&.bundle?
      rows = TicketQuantityHold.live.where(ticket_listing_id: @listing.id)
      rows = rows.where(ticket_tier_id: tier.id) if tier
      rows.sum(:quantity)
    end

    def taken(tier: nil)
      sold(tier: tier) + held(tier: tier) + outside(tier: tier) + blocked(tier: tier)
    end

    # Seats left for the listing, or for one tier (the lesser of its own seats
    # and the room's). A bundle's are its type's. nil = unlimited.
    def remaining(tier: nil)
      tier = tier.base_tier if tier&.bundle?
      return seated_remaining(tier) if seated?

      overall = capacity && [ capacity - taken, 0 ].max
      return overall unless tier

      own = tier.quantity && [ tier.quantity - taken(tier: tier), 0 ].max
      [ overall, own ].compact.min
    end

    # No seats left, or none left in a type anyone can buy: every type is
    # full, or marked sold out or hidden for this date (TicketTier#available?).
    def sold_out?
      return true if remaining&.zero?

      selling = @listing.ticket_tiers.active.reject(&:hidden).reject(&:bundle?).select(&:sells_online?)
      return false if selling.empty?

      open = selling.select(&:available?)
      open.empty? || open.all? { |tier| remaining(tier: tier)&.zero? }
    end

    # On a seated date, a type's seats left are the free seats in its zone
    # (and the standing room its areas have); the date's are every free seat
    # and standing place.
    def seated_remaining(tier)
      if tier
        standing = seating.standing_remaining(tier)
        free = seating.free_seats(tier).size
        tier.seated_zone? ? free + standing.to_i : standing.to_i
      else
        free = seating.seats.values.count { |s| !seating.taken?(s.id) }
        free + @listing.effective_seat_chart.sections.standing.sum { |a| [ a.standing_capacity - seating.standing_taken([ a.id ]), 0 ].max }
      end
    end

    # Would this many of each tier fit right now? requests: { tier => quantity }.
    def fits?(requests)
      if seated?
        return requests.all? { |tier, quantity| quantity <= seated_remaining(tier.base_tier) }
      end

      wanted = requests.values.sum
      overall = remaining
      return false if overall && wanted > overall

      requests.all? do |tier, quantity|
        left = tier.quantity && [ tier.quantity - taken(tier: tier), 0 ].max
        left.nil? || quantity <= left
      end
    end

    # Lock the listing (and the tiers asked for), check they still fit, then
    # yield so the caller writes its reservation under the same lock. Two
    # buyers racing for the last seat serialize here; the loser gets SoldOut.
    # excluding: as for new, positional so a bare { tier => n } still reads
    # as the requests.
    # seats: { tier => [seat ids] } on a seated date: those exact seats must
    # be free (a lapsed hold's reserved tickets on them are voided first, so
    # the one-live-ticket-per-seat index lets the new ones in), and the rest
    # of each request is best available.
    def self.reserve!(listing, requests, excluding = nil, seats: nil)
      listing.with_lock do
        TicketTier.where(id: requests.keys.map(&:id)).order(:id).lock.load
        if seats.present?
          wanted = seats.values.flatten.map(&:to_i).uniq
          void_stale_holds!(listing, wanted)
          taken = Seating.new(listing, excluding: excluding)
          gone = wanted.select { |id| taken.taken?(id) || !taken.seats.key?(id) }
          raise SoldOut if gone.any?

          seats.each do |tier, ids|
            allowed = tier.base_tier.zone_sections.select(&:seated?).map(&:id)
            raise SoldOut unless ids.all? { |id| allowed.include?(taken.seats[id.to_i].seat_section_id) }
          end
        end
        raise SoldOut unless new(listing, excluding: excluding).fits?(requests)

        yield
      end
    end

    # A hold that ran out still has reserved tickets on its seats until the
    # expiry job gets to it; under the lock, let them go now.
    def self.void_stale_holds!(listing, seat_ids)
      stale = Ticket.where(ticket_listing_id: listing.id, seat_id: seat_ids, status: "reserved").joins(:ticket_order).merge(TicketOrder.stale)
      orders = TicketOrder.where(id: stale.select(:ticket_order_id)).to_a
      return if orders.empty?

      orders.each do |order|
        order.ticket_purchase ? order.ticket_purchase.expire! : order.update!(status: "expired")
        order.tickets.where(status: "reserved").update_all(status: "void", updated_at: Time.current)
      end
    end

    private

    # A bundle's sales elsewhere are its type's.
    def outside_rows(tier)
      rows = TicketOutsideSale.where(ticket_listing_id: @listing.id)
      tier ? rows.where(ticket_tier_id: (tier.bundle? ? tier.base_tier : tier).id) : rows
    end

    # A bundle's tickets are its type's, remembering the bundle.
    def scope(tier)
      tickets = Ticket.where(ticket_listing_id: @listing.id)
      tickets = tickets.where.not(id: @excluding) if @excluding
      return tickets unless tier

      tier.bundle? ? tickets.where(bundle_tier_id: tier.id) : tickets.where(ticket_tier_id: tier.id)
    end
  end
end
