class My::ShowsController < ApplicationController
  def index
    @person = Current.user.person

    # Get groups the person is a member of
    @groups = @person.groups.active.order(:name)

    # Handle filter parameters
    @filter = params[:filter] || "my_assignments"
    @event_type_filter = params[:event_type] ? params[:event_type].split(",") : [ "show", "rehearsal", "meeting" ]
    @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

    # Get all shows from selected entities
    all_shows = []

    # Add person shows if selected
    if @entity_filter.include?("person")
      person_shows = Show.joins(production: { talent_pools: :people })
                        .where(people: { id: @person.id })
                        .where("date_and_time >= ?", Time.current)
                        .select("shows.*")
                        .distinct
      all_shows += person_shows.to_a
    end

    # Add group shows if selected
    @groups.each do |group|
      if @entity_filter.include?("group_#{group.id}")
        group_shows = Show.joins(production: { talent_pools: :groups })
                         .where(groups: { id: group.id })
                         .where("date_and_time >= ?", Time.current)
                         .select("shows.*")
                         .distinct
        all_shows += group_shows.to_a
      end
    end

    # Remove duplicates and filter by event type
    @shows = all_shows.uniq.select { |show| @event_type_filter.include?(show.event_type) }

    # Get productions from shows
    production_ids = @shows.map(&:production_id).uniq
    @productions = Production.where(id: production_ids).order(:name)

    # Order shows
    @shows = @shows.sort_by(&:date_and_time)

    # Get assignments for these shows (both person and group assignments)
    show_ids = @shows.map(&:id)
    assignments = ShowPersonRoleAssignment.where(show_id: show_ids)
                                         .where("(assignable_type = ? AND assignable_id = ?) OR (assignable_type = ? AND assignable_id IN (?))",
                                                "Person", @person.id, "Group", @groups.pluck(:id))
    @assignments_by_show = assignments.index_by(&:show_id)

    # Build mapping of which entities have assignments for each show
    @show_assignments = {}
    assignments.each do |assignment|
      @show_assignments[assignment.show_id] ||= []
      if assignment.assignable_type == "Person" && assignment.assignable_id == @person.id
        @show_assignments[assignment.show_id] << { type: "person", entity: @person }
      elsif assignment.assignable_type == "Group"
        group = @groups.find { |g| g.id == assignment.assignable_id }
        @show_assignments[assignment.show_id] << { type: "group", entity: group } if group
      end
    end

    # Filter to only shows with assignments if my_assignments filter is active
    if @filter == "my_assignments"
      @shows = @shows.select { |show| @show_assignments[show.id].present? }
      production_ids = @shows.map(&:production_id).uniq
      @productions = Production.where(id: production_ids).order(:name)
    end

    # Build a mapping of shows to their entities (for showing headshots)
    @show_entities = {}
    @shows.each do |show|
      # Check if person is assigned
      if @entity_filter.include?("person")
        person_show = Show.joins(production: { talent_pools: :people })
                         .where(people: { id: @person.id })
                         .where(id: show.id)
                         .exists?
        if person_show
          @show_entities[show.id] ||= []
          @show_entities[show.id] << { type: "person", entity: @person }
        end
      end

      # Check if any selected group is assigned
      @groups.each do |group|
        if @entity_filter.include?("group_#{group.id}")
          group_show = Show.joins(production: { talent_pools: :groups })
                          .where(groups: { id: group.id })
                          .where(id: show.id)
                          .exists?
          if group_show
            @show_entities[show.id] ||= []
            @show_entities[show.id] << { type: "group", entity: group }
          end
        end
      end
    end
  end

  def show
    @person = Current.user.person
    @groups = @person.groups.active

    @show = Show.joins(production: { talent_pools: :people })
               .where(people: { id: @person.id })
               .find(params[:id])
    @production = @show.production
    @show_person_role_assignments = @show.show_person_role_assignments.includes(:role)

    # Get my assignment for this show (check both person and group assignments)
    @my_assignment = @show_person_role_assignments.find do |a|
      (a.assignable_type == "Person" && a.assignable_id == @person.id) ||
      (a.assignable_type == "Group" && @groups.pluck(:id).include?(a.assignable_id))
    end
  end

  def calendar
    @person = Current.user.person

    # Get groups the person is a member of
    @groups = @person.groups.active.order(:name)

    @event_type_filter = params[:event_type] ? params[:event_type].split(",") : [ "show", "rehearsal", "meeting" ]
    @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

    # Determine date range for loading shows
    # Load from 6 months ago to 12 months in the future to support navigation
    start_date = 6.months.ago.beginning_of_month
    end_date = 12.months.from_now.end_of_month

    # Get all shows from selected entities with entity tracking
    shows_with_entities = {}

    # Add person shows if selected
    if @entity_filter.include?("person")
      person_shows = Show.joins(production: { talent_pools: :people })
                        .where(people: { id: @person.id })
                        .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                        .where(canceled: false)
                        .select("shows.*")
                        .distinct
      person_shows.each do |show|
        shows_with_entities[show.id] ||= { show: show, entities: [] }
        shows_with_entities[show.id][:entities] << "person"
      end
    end

    # Add group shows if selected
    @groups.each do |group|
      if @entity_filter.include?("group_#{group.id}")
        group_shows = Show.joins(production: { talent_pools: :groups })
                         .where(groups: { id: group.id })
                         .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                         .where(canceled: false)
                         .select("shows.*")
                         .distinct
        group_shows.each do |show|
          shows_with_entities[show.id] ||= { show: show, entities: [] }
          shows_with_entities[show.id][:entities] << "group_#{group.id}"
        end
      end
    end

    # Extract just the shows and filter by event type
    @shows = shows_with_entities.values.map { |h| h[:show] }.select { |show| @event_type_filter.include?(show.event_type) }

    # Order shows
    @shows = @shows.sort_by(&:date_and_time)

    # Group shows by month
    @shows_by_month = @shows.group_by { |show| show.date_and_time.beginning_of_month }

    # Get assignments for these shows
    show_ids = @shows.map(&:id)
    assignments = ShowPersonRoleAssignment.where(show_id: show_ids)
                                         .where("(assignable_type = ? AND assignable_id = ?) OR (assignable_type = ? AND assignable_id IN (?))",
                                                "Person", @person.id, "Group", @groups.pluck(:id))
    @assignments_by_show = assignments.index_by(&:show_id)

    # Build mapping of which entities have assignments for each show
    @show_assignments = {}
    assignments.each do |assignment|
      @show_assignments[assignment.show_id] ||= []
      if assignment.assignable_type == "Person" && assignment.assignable_id == @person.id
        @show_assignments[assignment.show_id] << { type: "person", entity: @person }
      elsif assignment.assignable_type == "Group"
        group = @groups.find { |g| g.id == assignment.assignable_id }
        @show_assignments[assignment.show_id] << { type: "group", entity: group } if group
      end
    end
  end
end
