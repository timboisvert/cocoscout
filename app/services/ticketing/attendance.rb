# frozen_string_literal: true

module Ticketing
  # Everyone holding a ticket, date by date, for a period: sold here, on
  # other sites, and comps, with a subtotal per production and each date's
  # breakdown by where the tickets came from. Tim, 2026-10-17: "how many
  # people were at our shows this weekend", without opening every date and
  # adding them up in his head. Counts only, never money.
  class Attendance
    Row = Data.define(:listing, :show, :here, :outside, :comps, :people, :came, :so_far, :sources, :upcoming) do
      def dates = 1
    end
    Group = Data.define(:production, :rows, :here, :outside, :comps, :people, :came, :so_far) do
      def dates = rows.size
    end
    Total = Data.define(:dates, :here, :outside, :comps, :people, :came, :so_far)

    # The breakdown's order: bought here first, in the channels' order, then
    # each other site, then comps.
    CHANNEL_ORDER = %w[online embed pass door_cash door_card door_tap door_pass].freeze

    attr_reader :organization, :from, :to, :production_id

    def initialize(organization, from:, to:, production_id: nil)
      @organization = organization
      @from = from
      @to = to
      @production_id = production_id.presence
    end

    def groups
      @groups ||= rows.group_by { |row| row.listing.production }.map do |production, rows|
        Group.new(production: production, rows: rows, **sums(rows))
      end.sort_by { |group| group.production.name.downcase }
    end

    def total
      @total ||= Total.new(dates: rows.size, **sums(rows))
    end

    def rows
      @rows ||= begin
        stats = ListingStats.for(listings)
        listings.map do |listing|
          s = stats.fetch(listing.id)
          Row.new(listing: listing, show: listing.show, here: s.sold - s.comps, outside: s.outside_sold, comps: s.comps,
                  people: s.sold + s.outside_sold, came: s.checked_in, so_far: s.sales_so_far?,
                  sources: sources_for(s), upcoming: listing.show.date_and_time > Time.current)
        end
      end
    end

    private

    def listings
      @listings ||= begin
        scope = organization.ticket_listings.joins(:show).includes(:production, :show)
                            .where(shows: { canceled: false, date_and_time: from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day })
                            .where.not(status: %w[draft canceled])
        scope = scope.where(production_id: production_id) if production_id
        scope.order("shows.date_and_time").to_a
      end
    end

    # [["Online", 31], ["Cash at the door", 5], ["Ticket Tailor", 15], ["Comps", 4]]
    def sources_for(stats)
      by_channel = stats.by_channel
      here = CHANNEL_ORDER.filter_map { |channel| [ ListingStats::CHANNELS.fetch(channel), by_channel[channel] ] if by_channel[channel].to_i.positive? }
      sites = stats.outside_by_site.map { |name, count, _cents| [ name, count ] }
      comps = stats.comps.positive? ? [ [ "Comps", stats.comps ] ] : []
      here + sites + comps
    end

    def sums(rows)
      { here: rows.sum(&:here), outside: rows.sum(&:outside), comps: rows.sum(&:comps), people: rows.sum(&:people),
        came: rows.sum(&:came), so_far: rows.any?(&:so_far) }
    end
  end
end
