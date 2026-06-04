# frozen_string_literal: true

# The /mics homepage and the global search box.
module Mics
  class PublicController < BaseController
    def index
      # Active hubs (Chicago at launch).
      @active_hubs = CityHub.where(status: CityHub.statuses[:active]).order(:name)

      @total_active_mics = Mic.active.unpaused.count
      @total_cities = @active_hubs.count
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
