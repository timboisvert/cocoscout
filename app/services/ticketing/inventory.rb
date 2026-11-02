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

    # The seat counts for many listings at once (ListingStats.for): what's
    # sold and held, by ticket type and by bundle, and what other sites sold.
    Counts = Data.define(:sold, :sold_in_bundles, :held, :held_in_bundles, :outside)

    # excluding: tickets that are giving up their seats in the same breath
    # (a move to another ticket type on the same date), so they don't count
    # against the seats they're moving into.
    # counts: this listing's Counts, already read for a batch; never with
    # excluding, since the counts would include the tickets moving.
    # tiers: the listing's ticket types, when the caller already has them.
    def initialize(listing, at: Time.current, excluding: nil, counts: nil, tiers: nil)
      @listing = listing
      @at = at
      @excluding = Array(excluding).map(&:to_i).presence
      @counts = counts unless @excluding
      @tiers = tiers
    end

    # { listing id => Counts } in five queries, however many listings (the
    # Home week was counting each show's seats on its own, 2026-11-02).
    def self.counts_for(listing_ids, at: Time.current)
      ids = Array(listing_ids)
      return {} if ids.empty?

      sold = Ticket.where(ticket_listing_id: ids, status: Ticket::SOLD_STATUSES)
      held = Ticket.where(ticket_listing_id: ids, status: "reserved").joins(:ticket_order).merge(TicketOrder.holding(at))
      by_listing = lambda do |grouped|
        out = Hash.new { |h, k| h[k] = {} }
        grouped.each { |(listing_id, tier_id), n| out[listing_id][tier_id] = n }
        out
      end
      sold_by_tier = by_listing.call(sold.group(:ticket_listing_id, :ticket_tier_id).count)
      sold_by_bundle = by_listing.call(sold.where.not(bundle_tier_id: nil).group(:ticket_listing_id, :bundle_tier_id).count)
      held_by_tier = by_listing.call(held.group(:ticket_listing_id, :ticket_tier_id).count)
      held_by_bundle = by_listing.call(held.where.not(bundle_tier_id: nil).group(:ticket_listing_id, :bundle_tier_id).count)
      outside = by_listing.call(TicketOutsideSale.where(ticket_listing_id: ids).group(:ticket_listing_id, :ticket_tier_id).sum(:tickets_sold))
      ids.to_h do |id|
        [ id, Counts.new(sold: sold_by_tier[id], sold_in_bundles: sold_by_bundle[id], held: held_by_tier[id],
                         held_in_bundles: held_by_bundle[id], outside: outside[id]) ]
      end
    end

    # The seats on sale: the ticket types' seats added up, when every type
    # has a count; otherwise there's no limit.
    def capacity
      # A bundle has no seats of its own: it uses its type's.
      tiers = active_tiers.reject(&:bundle?)
      tiers.sum(&:quantity) if tiers.any? && tiers.all?(&:quantity)
    end

    def sold(tier: nil)
      return counted(@counts.sold, @counts.sold_in_bundles, tier) if @counts

      scope(tier).where(status: Ticket::SOLD_STATUSES).count
    end

    def held(tier: nil)
      return counted(@counts.held, @counts.held_in_bundles, tier) if @counts

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
      @outside_by_tier ||= @counts&.outside || TicketOutsideSale.where(ticket_listing_id: @listing.id).group(:ticket_tier_id).sum(:tickets_sold)
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

    # No seats left, or none left in a type anyone can buy: every type is
    # full, or marked sold out or hidden for this date (TicketTier#available?).
    def sold_out?
      return true if remaining&.zero?

      selling = active_tiers.reject(&:hidden).reject(&:bundle?).select(&:sells_online?)
      return false if selling.empty?

      open = selling.select(&:available?)
      open.empty? || open.all? { |tier| remaining(tier: tier)&.zero? }
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
    # excluding: as for new, positional so a bare { tier => n } still reads
    # as the requests.
    def self.reserve!(listing, requests, excluding = nil)
      listing.with_lock do
        TicketTier.where(id: requests.keys.map(&:id)).order(:id).lock.load
        raise SoldOut unless new(listing, excluding: excluding).fits?(requests)

        yield
      end
    end

    private

    def active_tiers
      @tiers ? @tiers.reject(&:archived_at) : @listing.ticket_tiers.active.to_a
    end

    # One of the batch's counts, read the way scope(tier) filters: the whole
    # listing, one bundle's purchases, or one type's tickets.
    def counted(by_tier, by_bundle, tier)
      return by_tier.values.sum unless tier

      tier.bundle? ? by_bundle.fetch(tier.id, 0) : by_tier.fetch(tier.id, 0)
    end

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
