# frozen_string_literal: true

module My
  class AvailabilityController < ApplicationController
    def index
      @person = Current.user.person
      @groups = @person.groups.active.order(:name).to_a

      @filter = params[:filter] || session[:availability_filter] || "no_response"
      session[:availability_filter] = @filter

      # Handle entity filter
      @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

      @productions = Production.joins(talent_pools: :people).joins(:shows).where(people: { id: @person.id }).distinct

      # Check if user is a cast member of any productions (for showing filter bar even when filtered results are empty)
      @has_any_productions = @productions.any? || @groups.any? { |g| g.talent_pool_memberships.joins(talent_pool: :production).exists? }

      # Build selected group IDs for batch queries
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)
      groups_by_id = @groups.index_by(&:id)
      include_person = @entity_filter.include?("person")

      # Batch fetch ALL shows for person and selected groups in one query
      show_conditions = []
      show_params = []

      if include_person
        show_conditions << "people.id = ?"
        show_params << @person.id
      end

      if selected_group_ids.any?
        show_conditions << "groups.id IN (?)"
        show_params << selected_group_ids
      end

      # Single query for all shows with entity tracking
      all_shows_with_source = []

      if include_person
        person_shows = Show.joins(production: { talent_pools: :people })
                           .where(people: { id: @person.id })
                           .where.not(canceled: true)
                           .where("date_and_time > ?", Time.current)
                           .includes(:production, :location)
                           .distinct
                           .to_a
        person_shows.each { |s| all_shows_with_source << { show: s, entity_key: "person", entity: @person } }
      end

      if selected_group_ids.any?
        # Single batch query for all group shows with group_id tracking
        group_shows_with_group = Show
                                 .select("shows.*, groups.id as source_group_id")
                                 .joins(production: { talent_pools: :groups })
                                 .where(groups: { id: selected_group_ids })
                                 .where.not(canceled: true)
                                 .where("date_and_time > ?", Time.current)
                                 .includes(:production, :location)
                                 .distinct
                                 .to_a

        group_shows_with_group.each do |show|
          group_id = show.read_attribute(:source_group_id)
          group = groups_by_id[group_id]
          all_shows_with_source << { show: show, entity_key: "group_#{group_id}", entity: group }
        end
      end

      # Get unique shows
      @all_shows = all_shows_with_source.map { |item| item[:show] }.uniq.sort_by(&:date_and_time)
      all_show_ids = @all_shows.map(&:id)

      # Batch fetch ALL availabilities for person and selected groups
      availability_conditions = []
      availability_params = []

      if include_person
        availability_conditions << "(available_entity_type = 'Person' AND available_entity_id = ?)"
        availability_params << @person.id
      end

      selected_group_ids.each do |gid|
        availability_conditions << "(available_entity_type = 'Group' AND available_entity_id = ?)"
        availability_params << gid
      end

      all_availabilities = if availability_conditions.any?
                             ShowAvailability
                               .where(show_id: all_show_ids)
                               .where(availability_conditions.join(" OR "), *availability_params)
                               .to_a
      else
                             []
      end

      # Index availabilities by entity_key and show_id
      availabilities_by_entity = Hash.new { |h, k| h[k] = {} }
      availability_ids_by_entity = Hash.new { |h, k| h[k] = Set.new }

      all_availabilities.each do |avail|
        entity_key = if avail.available_entity_type == "Person"
                       "person"
        else
                       "group_#{avail.available_entity_id}"
        end
        availabilities_by_entity[entity_key][avail.show_id] = avail
        availability_ids_by_entity[entity_key].add(avail.show_id)
      end

      # Build entity_data using preloaded data
      @entity_data = {}

      if include_person
        person_shows = all_shows_with_source.select do |item|
          item[:entity_key] == "person"
        end.map { |item| item[:show] }.uniq.sort_by(&:date_and_time)
        person_avail_ids = availability_ids_by_entity["person"]
        @entity_data["person"] = {
          entity: @person,
          shows: person_shows,
          no_response_shows: person_shows.reject { |s| person_avail_ids.include?(s.id) },
          availabilities: availabilities_by_entity["person"]
        }
      end

      selected_group_ids.each do |group_id|
        entity_key = "group_#{group_id}"
        group = groups_by_id[group_id]
        group_shows = all_shows_with_source.select do |item|
          item[:entity_key] == entity_key
        end.map { |item| item[:show] }.uniq.sort_by(&:date_and_time)
        group_avail_ids = availability_ids_by_entity[entity_key]
        @entity_data[entity_key] = {
          entity: group,
          shows: group_shows,
          no_response_shows: group_shows.reject { |s| group_avail_ids.include?(s.id) },
          availabilities: availabilities_by_entity[entity_key]
        }
      end

      # Group shows by production for each entity
      @entity_data.each_value do |data|
        shows_by_production = {}
        data[:shows].group_by(&:production).each do |production, shows|
          shows_by_production[production] = shows.sort_by(&:date_and_time)
        end
        data[:shows_by_production] = shows_by_production
        data[:productions] = shows_by_production.keys.sort_by(&:name)
      end

      # Legacy shows_by_production for compatibility
      @shows_by_production = {}
      @productions.each do |production|
        @shows_by_production[production] = production.shows
                                                     .where.not(canceled: true)
                                                     .where("date_and_time > ?", Time.current)
                                                     .order(:date_and_time)
      end

      # Legacy variables for compatibility
      @no_response_shows = @all_shows.select do |show|
        @entity_data.values.any? { |data| data[:no_response_shows].include?(show) }
      end
      @availabilities = availabilities_by_entity["person"] || {}

      # Build show_entities mapping using preloaded data (no additional queries)
      # First, index shows by entity_key for O(1) lookup
      shows_by_entity_key = Hash.new { |h, k| h[k] = Set.new }
      all_shows_with_source.each do |item|
        shows_by_entity_key[item[:entity_key]].add(item[:show].id)
      end

      @show_entities = {}
      @all_shows.each do |show|
        @show_entities[show.id] = []

        # Check if person has this show using preloaded data
        if include_person && shows_by_entity_key["person"].include?(show.id)
          @show_entities[show.id] << { type: "person", entity: @person }
        end

        # Check if any selected group has this show using preloaded data
        selected_group_ids.each do |group_id|
          entity_key = "group_#{group_id}"
          if shows_by_entity_key[entity_key].include?(show.id)
            @show_entities[show.id] << { type: "group", entity: groups_by_id[group_id] }
          end
        end
      end

      # Build combined availabilities from all entities
      @combined_availabilities = {}
      @entity_data.each_value do |data|
        data[:availabilities].each do |show_id, availability|
          @combined_availabilities[show_id] = availability
        end
      end

      # Group shows by production
      @shows_by_production = @all_shows.group_by(&:production).transform_values do |shows|
        shows.sort_by(&:date_and_time)
      end
      @productions = @shows_by_production.keys.sort_by(&:name)
    end

    def calendar
      @person = Current.user.person
      @groups = @person.groups.active.order(:name).to_a

      # Handle event type filter - checkboxes
      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all

      # Handle entity filter (person, group_N)
      @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

      # Date range for calendar navigation (wider range to support month navigation)
      start_date = 6.months.ago.beginning_of_month
      end_date = 12.months.from_now.end_of_month

      # Build show_entity_pairs - array of { show:, entity_key:, entity: } hashes
      # This creates SEPARATE entries for each show/entity combination
      @show_entity_pairs = []

      include_person = @entity_filter.include?("person")
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      # Add person shows if selected
      if include_person
        person_shows = Show.joins(production: { talent_pools: :people })
                           .where(people: { id: @person.id })
                           .where.not(canceled: true)
                           .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                           .includes(:production, :location)
                           .order(:date_and_time)
                           .distinct
                           .to_a

        person_shows.each do |show|
          next unless @event_type_filter.include?(show.event_type)

          @show_entity_pairs << {
            show: show,
            entity_key: "person",
            entity: @person
          }
        end
      end

      # Add group shows in batch if selected
      if selected_group_ids.any?
        group_shows = Show
                      .select("shows.*, groups.id as source_group_id")
                      .joins(production: { talent_pools: :groups })
                      .where(groups: { id: selected_group_ids })
                      .where.not(canceled: true)
                      .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                      .includes(:production, :location)
                      .order(:date_and_time)
                      .distinct
                      .to_a

        group_shows.each do |show|
          next unless @event_type_filter.include?(show.event_type)

          group_id = show.read_attribute(:source_group_id)
          @show_entity_pairs << {
            show: show,
            entity_key: "group_#{group_id}",
            entity: groups_by_id[group_id]
          }
        end
      end

      # Sort by show date
      @show_entity_pairs.sort_by! { |pair| pair[:show].date_and_time }

      # Group by month using TimeWithZone (important for hash key matching)
      @pairs_by_month = @show_entity_pairs.group_by { |pair| pair[:show].date_and_time.beginning_of_month }

      # Get availabilities for all entities in batch - indexed by [show_id, entity_key]
      all_show_ids = @show_entity_pairs.map { |p| p[:show].id }.uniq

      availability_conditions = []
      availability_params = []

      if include_person
        availability_conditions << "(available_entity_type = 'Person' AND available_entity_id = ?)"
        availability_params << @person.id
      end

      selected_group_ids.each do |gid|
        availability_conditions << "(available_entity_type = 'Group' AND available_entity_id = ?)"
        availability_params << gid
      end

      all_availabilities = if availability_conditions.any? && all_show_ids.any?
                             ShowAvailability
                               .where(show_id: all_show_ids)
                               .where(availability_conditions.join(" OR "), *availability_params)
                               .to_a
      else
                             []
      end

      @availabilities = {}
      all_availabilities.each do |availability|
        entity_key = if availability.available_entity_type == "Person"
                       "person"
        else
                       "group_#{availability.available_entity_id}"
        end
        @availabilities[[ availability.show_id, entity_key ]] = availability
      end
    end

    def update
      @show = Show.find(params[:show_id])

      # Determine the entity based on entity_key parameter
      entity_key = params[:entity_key] || "person"
      if entity_key == "person"
        entity = Current.user.person
      else
        # Extract group ID from "group_123" format
        group_id = entity_key.sub(/^group_/, "").to_i
        entity = Current.user.person.groups.find(group_id)
      end

      @availability = ShowAvailability.find_or_initialize_by(available_entity: entity, show: @show)
      @availability.status = params[:status]
      if @availability.save
        render json: { status: @availability.status }
      else
        render json: { error: @availability.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end
  end
end
