# frozen_string_literal: true

module Ticketing
  # Each production's upcoming dates, soonest next date first: its next date
  # and the few after it, with their numbers (ListingStats), and how many it
  # has in all (Tim, 2026-10-07: "only the next one for each production", the
  # rest a click away). Ticketing's home page shows the first few
  # productions; the Productions page shows every one.
  class ComingUp
    DATES_PER_PRODUCTION = 6

    # One production: its dates in order as [listing, stats], the first being
    # the next, and how many upcoming dates it has in all.
    ProductionDates = Data.define(:production, :dates, :total) do
      def next_listing = dates.first.first
      def next_stats = dates.first.last
      def later = dates.drop(1)
    end

    def self.by_production(organization, dates_per_production: DATES_PER_PRODUCTION)
      new(organization).by_production(dates_per_production)
    end

    def initialize(organization)
      @organization = organization
    end

    def by_production(dates_per_production)
      ranked = upcoming.select("ticket_listings.id, ROW_NUMBER() OVER (PARTITION BY ticket_listings.production_id ORDER BY shows.date_and_time, ticket_listings.id) AS place")
      ids = TicketListing.from(ranked, :ranked).where("ranked.place <= ?", dates_per_production).pluck("ranked.id")
      totals = upcoming.group("ticket_listings.production_id").count
      listings = @organization.ticket_listings.joins(:show).includes(:production, show: %i[location location_space])
                              .where(id: ids).order("shows.date_and_time", :id).to_a
      stats = ListingStats.for(listings)
      listings.group_by(&:production_id).values.map do |dates|
        ProductionDates.new(production: dates.first.production, dates: dates.map { |listing| [ listing, stats.fetch(listing.id) ] },
                            total: totals.fetch(dates.first.production_id, dates.size))
      end
    end

    # Dates still to come that aren't canceled, without eager loading, so it
    # can be counted and ranked.
    def upcoming
      @organization.ticket_listings.joins(:show).where.not(status: "canceled").where(shows: { canceled: false })
                   .where("shows.date_and_time >= ?", Time.current.beginning_of_day)
    end
  end
end
