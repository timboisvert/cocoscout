# frozen_string_literal: true

# City listing pages — auto-generated for any city with at least one Mic;
# upgraded to a curated layout when a CityHub for that city exists.
module Mics
  class CitiesController < BaseController
    before_action :resolve_city

    helper_method :wheelchair_filter?, :within_miles, :hub_center, :filter_query_params,
                  :signup_filter, :active_when, :active_format, :accessibility_filter, :age_filter,
                  :distance_origin

    # Every list action below funnels through this same pipeline. The
    # URL action gives us a default for "when" (tonight/tomorrow/etc)
    # or "format" (standup/music/etc) but both axes are ALSO honored
    # from query params, so a path-based URL can carry an orthogonal
    # filter alongside it — i.e. /chicago-il/tonight?format=music
    # works the same as /chicago-il/standup?when=tomorrow. Filters are
    # truly independent; no more "pick one and lose the other."

    def show
      @mics = filtered_sorted_mics
      @view = view_param
      @bucket_title = bucket_title
      render(active_bucket_layout? ? :bucket : :show)
    end

    def tonight     ; show end
    def tomorrow    ; show end
    def this_week   ; show end
    def by_format   ; show end

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
    # merge into any sidebar/toggle link URL. Every filter axis lives
    # here so we don't drop them when the user clicks across axes.
    def filter_query_params
      qp = {}
      qp[:view]   = "map"          if view_param == "map"
      qp[:within] = within_miles   if within_miles
      qp[:signup] = signup_filter  if signup_filter
      qp[:access] = accessibility_filter if accessibility_filter
      qp[:age]    = age_filter     if age_filter
      qp[:when]   = active_when    if active_when && action_name == "show"
      qp[:format] = active_format  if active_format && action_name != "by_format"
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

    # Active "when" axis. Path takes priority (so an explicit /tonight
    # URL is canonical); a `?when=` qp lets a non-bucket page combine
    # axes (e.g. /chicago-il/standup?when=tonight).
    def active_when
      v = case action_name
      when "tonight", "tomorrow" then action_name
      when "this_week" then "this-week"
      else
        params[:when].to_s
      end
      %w[tonight tomorrow this-week].include?(v) ? v : nil
    end

    # Active "format" axis. Path takes priority for /by_format URLs.
    def active_format
      v = if action_name == "by_format"
        params[:format_segment].to_s.tr("-", "_")
      else
        params[:format].to_s.tr("-", "_")
      end
      Mic.formats.key?(v) ? v : nil
    end

    # Accessibility levels: "fully" / "partial" / "any". Backward-
    # compatible with the legacy `wheelchair=1` qp which just means
    # "fully" for the purposes of filtering.
    def accessibility_filter
      v = params[:access].to_s
      return v if %w[fully partial].include?(v)
      wheelchair_filter? ? "fully" : nil
    end

    def age_filter
      params[:age].to_s == "21" ? "21" : nil
    end

    # Distance origin — a hash {lat, lng, label, kind}. Defaults to the
    # hub center; user can override via session (geolocation pick or a
    # custom address geocoded server-side).
    def distance_origin
      sess = session[:mics_origin]
      if sess && sess["lat"].present? && sess["lng"].present?
        { lat: sess["lat"].to_f, lng: sess["lng"].to_f,
          label: sess["label"].to_s, kind: sess["kind"].to_s }
      elsif (center = hub_center)
        { lat: center[0], lng: center[1],
          label: @hub ? "#{@hub.name} center" : "City center",
          kind: "city_center" }
      end
    end

    # Filtered + sorted mic list for the canonical show + bucket views.
    # Every filter axis is applied independently from every other one.
    def filtered_sorted_mics
      base = apply_filters(scoped_mics).includes(:venue, :tags).to_a

      # When-bucket — narrow to the time window if one is active.
      base = filter_by_when(base) if active_when

      # Format filter is a SQL clause when it's the only thing narrowing
      # (path-based by_format already applied it in scope); when arriving
      # via query param we filter in Ruby on the already-fetched array
      # so we don't double-query. Both paths converge here for safety.
      if active_format && !base.empty?
        fmt_int = Mic.formats[active_format]
        base = base.select { |m| m.format == active_format || m.read_attribute(:format) == fmt_int }
      end

      # Sort by next occurrence ascending, name as tiebreaker.
      base.sort_by do |m|
        occ = m.next_occurrences(limit: 1).first
        [ occ ? occ[:starts_at] : Time.current + 100.years, m.name.to_s.downcase ]
      end
    end

    def filter_by_when(mics)
      window =
        case active_when
        when "tonight"   then [ Time.current.beginning_of_day, Time.current.end_of_day ]
        when "tomorrow"  then [ (Date.current + 1).beginning_of_day, (Date.current + 1).end_of_day ]
        when "this-week" then [ Time.current, 7.days.from_now ]
        end
      return mics unless window
      start_at, end_at = window
      mics.select do |m|
        occ = m.next_occurrences(limit: 1).first
        occ && occ[:starts_at] >= start_at && occ[:starts_at] <= end_at
      end
    end

    def apply_filters(scope)
      scope = apply_wheelchair_filter(scope)
      scope = apply_distance_filter(scope)
      scope = apply_signup_filter(scope)
      scope = apply_age_filter(scope)
      scope
    end

    def apply_age_filter(scope)
      return scope unless age_filter == "21"
      scope.where("mics.min_age >= ?", 21)
    end

    # Whether to render with the bucket layout (extra title strip). True
    # when any "when" filter is active OR a format filter is active.
    def active_bucket_layout?
      active_when.present? || active_format.present?
    end

    def bucket_title
      bits = []
      if active_when
        bits << case active_when
        when "tonight"   then "Tonight"
        when "tomorrow"  then "Tomorrow"
        when "this-week" then "This week"
        end
      end
      bits << "#{helpers.mics_format_label(active_format)} mics" if active_format
      return nil if bits.empty?
      bits.join(" · ")
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

    # 3-level accessibility filter. "fully" only matches venues + mics
    # explicitly marked fully accessible; "partial" matches BOTH
    # partially-accessible AND fully-accessible (anyone needing partial
    # access can also use a fully accessible room). Legacy `wheelchair=1`
    # qp routes through accessibility_filter and lands as "fully".
    def apply_wheelchair_filter(scope)
      level = accessibility_filter
      return scope unless level
      levels = level == "partial" ? %w[fully partial] : [ "fully" ]
      json_levels = levels.to_json
      scope.joins(:venue).where(
        "(mics.accessibility->>'wheelchair_level' = ANY (ARRAY[?])) OR " \
        "(venues.accessibility->>'wheelchair_level' = ANY (ARRAY[?]))",
        levels, levels
      )
    end

    def apply_distance_filter(scope)
      return scope unless within_miles
      origin = distance_origin
      return scope unless origin
      scope.within_miles_of(origin[:lat], origin[:lng], within_miles)
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
