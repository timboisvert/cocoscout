# frozen_string_literal: true

# The /mics homepage and the global search box.
module Mics
  class PublicController < BaseController
    def index
      # Active hubs (Chicago at launch).
      @active_hubs = CityHub.where(status: CityHub.statuses[:active]).order(:name)

      # Cities are listed only for venues that aren't already rolled up
      # into a hub. Forest Park, Berwyn, etc. live under the Chicago hub
      # and should not appear as standalone cities.
      @top_cities = Mic.active.joins(:venue)
                       .where(venues: { city_hub_id: nil })
                       .group("venues.city", "venues.state")
                       .order(Arel.sql("COUNT(*) DESC"))
                       .limit(8)
                       .count

      @total_active_mics = Mic.active.count
      # Distinct "places" = active hubs + non-hub cities, so the count
      # matches what the user sees in the grid.
      hub_states = @active_hubs.count
      non_hub_states = Mic.active.joins(:venue)
                          .where(venues: { city_hub_id: nil })
                          .distinct.count(Arel.sql("venues.city || ',' || venues.state"))
      @total_cities = hub_states + non_hub_states
    end

    def search
      @query = params[:q].to_s.strip
      @results =
        if @query.length >= 2
          like = "%#{@query.downcase}%"
          Mic.active
             .joins(:venue)
             .where("LOWER(mics.name) LIKE :q OR LOWER(venues.name) LIKE :q " \
                    "OR LOWER(venues.city) LIKE :q OR LOWER(venues.neighborhood) LIKE :q",
                    q: like)
             .includes(:venue)
             .limit(50)
        else
          Mic.none
        end
    end
  end
end
