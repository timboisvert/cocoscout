# frozen_string_literal: true

# City listing pages — auto-generated for any city with at least one Mic;
# upgraded to a curated layout when a CityHub for that city exists.
module Mics
  class CitiesController < BaseController
    before_action :resolve_city

    helper_method :wheelchair_filter?, :within_miles, :hub_center, :filter_query_params, :signup_filter

    def show
      base = apply_filters(scoped_mics).includes(:venue, :tags).to_a
      # Order by each mic's next occurrence, alphabetical only as
      # tiebreaker. Same shape as the bucket views.
      @mics = base.sort_by do |m|
        occ = m.next_occurrences(limit: 1).first
        [ occ ? occ[:starts_at] : Time.current + 100.years, m.name.to_s.downcase ]
      end
      @view = view_param
      render :show
    end

    def tonight
      @mics = upcoming_in_city_within(Time.current.beginning_of_day, Time.current.end_of_day)
      @bucket_title = "Tonight"
      @view = view_param
      render :bucket
    end

    def tomorrow
      tomorrow = Date.current + 1
      @mics = upcoming_in_city_within(tomorrow.beginning_of_day, tomorrow.end_of_day)
      @bucket_title = "Tomorrow"
      @view = view_param
      render :bucket
    end

    def this_week
      @mics = upcoming_in_city_within(Time.current, 7.days.from_now)
      @bucket_title = "This week"
      @view = view_param
      render :bucket
    end

    def by_format
      fmt = params[:format_segment].to_s.tr("-", "_")
      head :not_found and return unless Mic.formats.key?(fmt)
      base = scoped_mics.where(format: Mic.formats[fmt])
      @mics = apply_filters(base).includes(:venue, :tags).order(:name)
      @bucket_title = "#{helpers.mics_format_label(fmt)} mics"
      @view = view_param
      render :bucket
    end

    def calendar
      send_data MicIcsBuilder.for_city(@city, @state, mics: scoped_mics.to_a),
                type: "text/calendar",
                disposition: "attachment",
                filename: "#{@slug}.ics"
    end

    # Legacy `/map` URL — just redirect to the show page with ?view=map.
    def map
      redirect_to mics_city_path(@slug, view: "map", **map_filter_params)
    end

    private

    def view_param
      params[:view].to_s == "map" ? "map" : "list"
    end

    def map_filter_params
      params.permit(:wheelchair, :within, :signup).to_h.compact_blank
    end

    # Carries the current view/filter state forward as a hash you can
    # merge into any sidebar/toggle link URL.
    def filter_query_params
      qp = {}
      qp[:view]       = "map" if view_param == "map"
      qp[:wheelchair] = 1     if wheelchair_filter?
      qp[:within]     = within_miles if within_miles
      qp[:signup]     = signup_filter if signup_filter
      qp
    end

    def wheelchair_filter?
      ActiveModel::Type::Boolean.new.cast(params[:wheelchair])
    end

    # Returns "online", "in_person", or nil. Other input is rejected so
    # the param can't be coerced into something weird.
    def signup_filter
      v = params[:signup].to_s
      %w[online in_person].include?(v) ? v : nil
    end

    # Permitted distance options for the sidebar filter. Empty string =
    # no filter.
    DISTANCE_OPTIONS = [ 1, 3, 5, 10, 25 ].freeze

    def within_miles
      m = params[:within].to_i
      DISTANCE_OPTIONS.include?(m) ? m : nil
    end

    # Anchor for distance filter. Hub's own coords if set; otherwise the
    # centroid of its venues. Returns [lat, lng] or nil.
    def hub_center
      return nil unless @hub
      return [ @hub.lat, @hub.lng ] if @hub.lat && @hub.lng
      Rails.cache.fetch("mics:hub_center:#{@hub.id}", expires_in: 1.hour) do
        avg = Venue.where(city_hub_id: @hub.id).where.not(lat: nil)
                   .pick(Arel.sql("AVG(lat)"), Arel.sql("AVG(lng)"))
        avg && avg.map(&:to_f)
      end
    end

    def apply_filters(scope)
      scope = apply_wheelchair_filter(scope)
      scope = apply_distance_filter(scope)
      scope = apply_signup_filter(scope)
      scope
    end

    # `signup_method` enum: online (0), in_person (1), online_and_in_person (2).
    # Filtering for "online" should match both online and online_and_in_person;
    # filtering for "in_person" should match both in_person and online_and_in_person.
    def apply_signup_filter(scope)
      case signup_filter
      when "online"    then scope.where(signup_method: %i[online online_and_in_person])
      when "in_person" then scope.where(signup_method: %i[in_person online_and_in_person])
      else scope
      end
    end

    def apply_wheelchair_filter(scope)
      return scope unless wheelchair_filter?
      scope.joins(:venue).where(
        "(mics.accessibility @> ?::jsonb) OR (venues.accessibility @> ?::jsonb)",
        { wheelchair: true }.to_json, { wheelchair: true }.to_json
      )
    end

    def apply_distance_filter(scope)
      return scope unless within_miles
      lat, lng = hub_center
      return scope if lat.blank? || lng.blank?
      scope.within_miles_of(lat, lng, within_miles)
    end

    def resolve_city
      @slug = params[:city_slug].to_s.downcase
      @hub = CityHub.find_by(slug: @slug)
      @city, @state =
        if @hub
          [ @hub.name, @hub.state ]
        else
          city_state_from_slug(@slug)
        end

      if @city.blank?
        head :not_found and return
      end

      # If the resolved city is a "satellite" of a hub (every venue in
      # that city belongs to the same hub, and that hub's slug isn't this
      # one), 301 to the hub. Keeps Forest Park traffic on /chicago-il.
      if @hub.nil? && (satellite_hub = satellite_hub_for(@city, @state))
        redirect_to mics_city_path(satellite_hub.slug), status: :moved_permanently and return
      end

      @any_mics = scoped_mics.exists?
      @mics = Mic.none unless @any_mics

      # Sidebar: cities with active mics, excluding hub-rolled venues.
      # Empty hash → sidebar hides the section entirely.
      @other_cities = Mic.active.unpaused.joins(:venue)
                         .where(venues: { city_hub_id: nil })
                         .group("venues.city", "venues.state")
                         .order(Arel.sql("COUNT(*) DESC"))
                         .count
    end

    # All active, *unpaused* mics that belong on this listing — either
    # rolled up via the hub, or matched on raw city/state when there's
    # no hub. Paused mics still exist for search + favorites but get
    # filtered out of these public listings.
    def scoped_mics
      base = if @hub
        Mic.active.in_hub(@hub)
      else
        Mic.in_city(@city, @state).active
      end
      base.unpaused
    end

    # If every venue in the given city/state belongs to the same hub,
    # return that hub. Otherwise nil. Used to redirect satellite cities
    # to the parent hub.
    def satellite_hub_for(city, state)
      hub_ids = Venue.where(city: city, state: state)
                     .where.not(city_hub_id: nil)
                     .distinct
                     .pluck(:city_hub_id)
      return nil unless hub_ids.size == 1
      orphans = Venue.where(city: city, state: state, city_hub_id: nil).exists?
      return nil if orphans
      CityHub.find_by(id: hub_ids.first)
    end

    # Returns mics whose next occurrence falls in the window, sorted by
    # start time ascending, with name as tiebreaker.
    def upcoming_in_city_within(start_at, end_at)
      mics = apply_filters(scoped_mics).to_a
      tagged = mics.filter_map do |m|
        occ = m.next_occurrences(limit: 1).first
        next unless occ && occ[:starts_at] >= start_at && occ[:starts_at] <= end_at
        [ occ[:starts_at], m ]
      end
      tagged.sort_by { |starts_at, m| [ starts_at, m.name.to_s.downcase ] }.map(&:last)
    end
  end
end
