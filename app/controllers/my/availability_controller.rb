class My::AvailabilityController < ApplicationController
  def index
    @person = Current.user.person
    @groups = @person.groups.active.order(:name)

    @filter = (params[:filter] || session[:availability_filter] || "no_response")
    session[:availability_filter] = @filter

    # Handle entity filter
    @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

    @productions = Production.joins(talent_pools: :people).joins(:shows).where(people: { id: @person.id }).distinct

    # Get all upcoming non-canceled shows from selected entities
    all_shows = []

    # Add person shows if selected
    if @entity_filter.include?("person")
      person_shows = Show.joins(production: { talent_pools: :people })
        .where(people: { id: @person.id })
        .where.not(canceled: true)
        .where("date_and_time > ?", Time.current)
        .order(:date_and_time)
        .distinct
      all_shows += person_shows.to_a
    end

    # Add group shows if selected
    @groups.each do |group|
      if @entity_filter.include?("group_#{group.id}")
        group_shows = Show.joins(production: { talent_pools: :groups })
          .where(groups: { id: group.id })
          .where.not(canceled: true)
          .where("date_and_time > ?", Time.current)
          .order(:date_and_time)
          .distinct
        all_shows += group_shows.to_a
      end
    end

    @all_shows = all_shows.uniq.sort_by(&:date_and_time)

    # Get shows with no response for each entity
    @entity_data = {}

    if @entity_filter.include?("person")
      person_availability_ids = ShowAvailability.where(available_entity: @person).pluck(:show_id)
      person_shows = Show.joins(production: { talent_pools: :people })
        .where(people: { id: @person.id })
        .where.not(canceled: true)
        .where("date_and_time > ?", Time.current)
        .order(:date_and_time)
        .distinct
      @entity_data["person"] = {
        entity: @person,
        shows: person_shows.to_a,
        no_response_shows: person_shows.where.not(id: person_availability_ids).to_a,
        availabilities: ShowAvailability.where(available_entity: @person).index_by(&:show_id)
      }
    end

    @groups.each do |group|
      if @entity_filter.include?("group_#{group.id}")
        group_availability_ids = ShowAvailability.where(available_entity: group).pluck(:show_id)
        group_shows = Show.joins(production: { talent_pools: :groups })
          .where(groups: { id: group.id })
          .where.not(canceled: true)
          .where("date_and_time > ?", Time.current)
          .order(:date_and_time)
          .distinct
        @entity_data["group_#{group.id}"] = {
          entity: group,
          shows: group_shows.to_a,
          no_response_shows: group_shows.where.not(id: group_availability_ids).to_a,
          availabilities: ShowAvailability.where(available_entity: group).index_by(&:show_id)
        }
      end
    end

    # Group shows by production for each entity
    @entity_data.each do |entity_key, data|
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
    @no_response_shows = @all_shows.select { |show|
      @entity_data.values.any? { |data| data[:no_response_shows].include?(show) }
    }
    @availabilities = ShowAvailability.where(available_entity: @person).index_by(&:show_id)

    # Build show_entities mapping (which entities each show belongs to)
    @show_entities = {}
    @all_shows.each do |show|
      @show_entities[show.id] = []

      # Check if person has this show
      if @entity_filter.include?("person")
        person_show = Show.joins(production: { talent_pools: :people })
                         .where(people: { id: @person.id })
                         .where(id: show.id)
                         .exists?
        if person_show
          @show_entities[show.id] << { type: "person", entity: @person }
        end
      end

      # Check if any selected group has this show
      @groups.each do |group|
        if @entity_filter.include?("group_#{group.id}")
          group_show = Show.joins(production: { talent_pools: :groups })
                          .where(groups: { id: group.id })
                          .where(id: show.id)
                          .exists?
          if group_show
            @show_entities[show.id] << { type: "group", entity: group }
          end
        end
      end
    end

    # Build combined availabilities from all entities
    @combined_availabilities = {}
    @entity_data.each do |entity_key, data|
      data[:availabilities].each do |show_id, availability|
        @combined_availabilities[show_id] = availability
      end
    end

    # Group shows by production
    @shows_by_production = @all_shows.group_by(&:production).transform_values { |shows| shows.sort_by(&:date_and_time) }
    @productions = @shows_by_production.keys.sort_by(&:name)
  end

  def calendar
    @event_filter = params[:event_type] || "all"

    # Get all upcoming non-canceled shows
    @shows = Show.joins(production: { talent_pools: :people })
      .where(people: { id: Current.user.person.id })
      .where.not(canceled: true)
      .where("date_and_time > ?", Time.current)
      .order(:date_and_time)
      .distinct

    # Apply event type filter
    unless @event_filter == "all"
      @shows = @shows.where(event_type: @event_filter)
    end

    # Group shows by month
    @shows_by_month = @shows.group_by { |show| show.date_and_time.beginning_of_month }

    @availabilities = ShowAvailability.where(available_entity: Current.user.person).index_by(&:show_id)
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
