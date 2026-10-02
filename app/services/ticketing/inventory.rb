# frozen_string_literal: true

module Ticketing
  # The only code that answers "how many seats are left?" for a listing.
  #
  # A seat is taken by a sold ticket (valid or checked in), and by a reserved
  # one while its order is still holding it — wherever the ticket was sold.
  # Tickets sold on other sites later are tickets here too, so the same count
  # keeps every site in balance. Nothing else in the app counts tickets.
  #
  # Capacity is the listing's, or else the sum of its tiers' seats when every
  # tier has a count; nil means no limit. A tier's own seats cap it too.
  class Inventory
    class SoldOut < StandardError; end

    def initialize(listing, at: Time.current)
      @listing = listing
      @at = at
    end

    # The seats on sale: the ticket types' seats added up, when every type
    # has a count; otherwise there's no limit.
    def capacity
      tiers = @listing.ticket_tiers.active.to_a
      tiers.sum(&:quantity) if tiers.any? && tiers.all?(&:quantity)
    end

    def sold(tier: nil)
      scope(tier).where(status: Ticket::SOLD_STATUSES).count
    end

    def held(tier: nil)
      scope(tier).where(status: "reserved").joins(:ticket_order).merge(TicketOrder.holding(@at)).count
    end

    def taken(tier: nil)
      sold(tier: tier) + held(tier: tier)
    end

    # Seats left for the listing, or for one tier (the lesser of its own seats
    # and the room's). nil = unlimited.
    def remaining(tier: nil)
      overall = capacity && [ capacity - taken, 0 ].max
      return overall unless tier

      own = tier.quantity && [ tier.quantity - taken(tier: tier), 0 ].max
      [ overall, own ].compact.min
    end

    def sold_out?
      left = remaining
      return left.zero? unless left.nil?

      selling = @listing.ticket_tiers.active.reject(&:hidden)
      selling.any? && selling.all? { |tier| remaining(tier: tier)&.zero? }
    end

    # Would this many of each tier fit right now? requests: { tier => quantity }.
    def fits?(requests)
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
    def self.reserve!(listing, requests)
      listing.with_lock do
        TicketTier.where(id: requests.keys.map(&:id)).order(:id).lock.load
        raise SoldOut unless new(listing).fits?(requests)

        yield
      end
    end

    private

    def scope(tier)
      tickets = Ticket.where(ticket_listing_id: @listing.id)
      tier ? tickets.where(ticket_tier_id: tier.id) : tickets
    end
  end
end
