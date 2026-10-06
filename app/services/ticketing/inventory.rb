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

    def initialize(listing, at: Time.current)
      @listing = listing
      @at = at
    end

    # The seats on sale: the ticket types' seats added up, when every type
    # has a count; otherwise there's no limit.
    def capacity
      # A bundle has no seats of its own: it uses its type's.
      tiers = @listing.ticket_tiers.active.reject(&:bundle?)
      tiers.sum(&:quantity) if tiers.any? && tiers.all?(&:quantity)
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
      rows = TicketOutsideSale.where(ticket_listing_id: @listing.id)
      rows = rows.where(ticket_tier_id: (tier.bundle? ? tier.base_tier : tier).id) if tier
      rows.joins(:ticket_source).group("ticket_sources.name").sum(:tickets_sold).map { |name, n| "#{n} on #{name}" }.to_sentence
    end

    def taken(tier: nil)
      sold(tier: tier) + held(tier: tier) + outside(tier: tier)
    end

    # Seats left for the listing, or for one tier (the lesser of its own seats
    # and the room's). A bundle's are its type's. nil = unlimited.
    def remaining(tier: nil)
      tier = tier.base_tier if tier&.bundle?
      overall = capacity && [ capacity - taken, 0 ].max
      return overall unless tier

      own = tier.quantity && [ tier.quantity - taken(tier: tier), 0 ].max
      [ overall, own ].compact.min
    end

    def sold_out?
      left = remaining
      return left.zero? unless left.nil?

      selling = @listing.ticket_tiers.active.reject(&:hidden).reject(&:bundle?)
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

    # A bundle's tickets are its type's, remembering the bundle.
    def scope(tier)
      tickets = Ticket.where(ticket_listing_id: @listing.id)
      return tickets unless tier

      tier.bundle? ? tickets.where(bundle_tier_id: tier.id) : tickets.where(ticket_tier_id: tier.id)
    end
  end
end
