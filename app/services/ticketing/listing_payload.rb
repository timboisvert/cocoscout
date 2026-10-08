# frozen_string_literal: true

module Ticketing
  # The one description of a listing: what the show is, when and where, who
  # can come, and what each ticket costs all-in. The public page's
  # search-engine data reads from it today; other ticket sites will get the
  # same description later, so every place a show appears says the same thing.
  class ListingPayload
    def self.for(listing)
      new(listing).to_h
    end

    def initialize(listing)
      @listing = listing
      @show = listing.show
    end

    def to_h
      inventory = @listing.inventory
      {
        title: @listing.display_title,
        production: @listing.production.name,
        description: @listing.effective_description,
        organizer: @listing.organization.name,
        starts_at: @listing.starts_at&.iso8601,
        ends_at: @listing.ends_at&.iso8601,
        selling: @listing.selling?,
        sold_out: inventory.sold_out?,
        online: @show.is_online,
        minimum_age: @listing.effective_minimum_age,
        venue: venue,
        currency: "usd",
        fee_mode: @listing.effective_fee_mode,
        tiers: @listing.ticket_tiers.active.reject(&:hidden).reject(&:unlisted?).map { |tier| tier_payload(tier, inventory) }
      }
    end

    private

    def venue
      location = @show.location
      return nil unless location

      {
        name: location.name,
        room: @show.location_space&.name,
        address1: location.address1,
        address2: location.address2,
        city: location.city,
        state: location.state,
        postal_code: location.postal_code
      }
    end

    def tier_payload(tier, inventory)
      {
        id: tier.id,
        name: tier.name,
        description: tier.description,
        price_cents: tier.price_cents,
        all_in_price_cents: TicketPricing.all_in_price_cents(@listing, tier),
        remaining: inventory.remaining(tier: tier),
        selling: tier.selling?
      }
    end
  end
end
