# frozen_string_literal: true

module My
  class ShowsController < ApplicationController
    def index
      @person = Current.user.person

      # Get groups the person is a member of
      @groups = @person.groups.active.order(:name).to_a
      group_ids = @groups.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      # Handle filter parameters
      @filter = params[:filter] || "my_assignments"
      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all
      @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

      # Check if user has ANY shows at all (before filtering) for showing filter bar
      person_has_shows = Show.joins(production: { talent_pools: :people })
                             .where(people: { id: @person.id })
                             .where("date_and_time >= ?", Time.current)
                             .exists?
      groups_have_shows = group_ids.any? && Show.joins(production: { talent_pools: :groups })
                                                .where(groups: { id: group_ids })
                                                .where("date_and_time >= ?", Time.current)
                                                .exists?
      @has_any_shows = person_has_shows || groups_have_shows

      include_person = @entity_filter.include?("person")
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)

      # Get all shows from selected entities with entity tracking
      shows_with_source = []

      # Add person shows if selected
      if include_person
        person_shows = Show.joins(production: { talent_pools: :people })
                           .where(people: { id: @person.id })
                           .where("date_and_time >= ?", Time.current)
                           .includes(:production, :location)
                           .select("shows.*")
                           .distinct
                           .to_a
        person_shows.each { |s| shows_with_source << { show: s, entity_key: "person", entity: @person } }
      end

      # Add group shows in batch if selected
      if selected_group_ids.any?
        group_shows = Show.select("shows.*, groups.id as source_group_id")
                          .joins(production: { talent_pools: :groups })
                          .where(groups: { id: selected_group_ids })
                          .where("date_and_time >= ?", Time.current)
                          .includes(:production, :location)
                          .distinct
                          .to_a
        group_shows.each do |show|
          group_id = show.read_attribute(:source_group_id)
          shows_with_source << { show: show, entity_key: "group_#{group_id}", entity: groups_by_id[group_id] }
        end
      end

      # Remove duplicates and filter by event type
      @shows = shows_with_source.map do |item|
        item[:show]
      end.uniq.select { |show| @event_type_filter.include?(show.event_type) }

      # Get productions from shows
      production_ids = @shows.map(&:production_id).uniq
      @productions = Production.where(id: production_ids).order(:name)

      # Order shows
      @shows = @shows.sort_by(&:date_and_time)

      # Get assignments for these shows (both person and group assignments) - use group_ids instead of pluck
      show_ids = @shows.map(&:id)
      assignments = ShowPersonRoleAssignment.where(show_id: show_ids)
                                            .where("(assignable_type = ? AND assignable_id = ?) OR (assignable_type = ? AND assignable_id IN (?))",
                                                   "Person", @person.id, "Group", group_ids)
                                            .to_a
      @assignments_by_show = assignments.index_by(&:show_id)

      # Build mapping of which entities have assignments for each show
      @show_assignments = {}
      assignments.each do |assignment|
        @show_assignments[assignment.show_id] ||= []
        if assignment.assignable_type == "Person" && assignment.assignable_id == @person.id
          @show_assignments[assignment.show_id] << { type: "person", entity: @person }
        elsif assignment.assignable_type == "Group"
          group = groups_by_id[assignment.assignable_id]
          @show_assignments[assignment.show_id] << { type: "group", entity: group } if group
        end
      end

      # Filter to only shows with assignments if my_assignments filter is active
      if @filter == "my_assignments"
        @shows = @shows.select { |show| @show_assignments[show.id].present? }
        production_ids = @shows.map(&:production_id).uniq
        @productions = Production.where(id: production_ids).order(:name)
      end

      # Build a mapping of shows to their entities using preloaded data (no additional queries)
      shows_by_entity_key = Hash.new { |h, k| h[k] = Set.new }
      shows_with_source.each { |item| shows_by_entity_key[item[:entity_key]].add(item[:show].id) }

      @show_entities = {}
      @shows.each do |show|
        @show_entities[show.id] = []

        # Check if person is assigned using preloaded data
        if include_person && shows_by_entity_key["person"].include?(show.id)
          @show_entities[show.id] << { type: "person", entity: @person }
        end

        # Check if any selected group is assigned using preloaded data
        selected_group_ids.each do |gid|
          if shows_by_entity_key["group_#{gid}"].include?(show.id)
            @show_entities[show.id] << { type: "group", entity: groups_by_id[gid] }
          end
        end
      end
    end

    def show
      @person = Current.user.person
      @groups = @person.groups.active.to_a
      group_ids = @groups.map(&:id)

      # Find the show if user has access via:
      # 1. Person is in the production's talent pool
      # 2. Person's group is in the production's talent pool
      # 3. Person has a direct role assignment
      # 4. Person's group has a role assignment
      @show = Show.where(id: params[:id])
                  .where(
                    "EXISTS (SELECT 1 FROM talent_pools
                             INNER JOIN talent_pool_memberships ON talent_pools.id = talent_pool_memberships.talent_pool_id
                             WHERE talent_pools.production_id = shows.production_id
                             AND talent_pool_memberships.member_type = 'Person'
                             AND talent_pool_memberships.member_id = ?) OR
                     EXISTS (SELECT 1 FROM talent_pools
                             INNER JOIN talent_pool_memberships ON talent_pools.id = talent_pool_memberships.talent_pool_id
                             WHERE talent_pools.production_id = shows.production_id
                             AND talent_pool_memberships.member_type = 'Group'
                             AND talent_pool_memberships.member_id IN (?)) OR
                     EXISTS (SELECT 1 FROM show_person_role_assignments
                             WHERE show_person_role_assignments.show_id = shows.id
                             AND show_person_role_assignments.assignable_type = 'Person'
                             AND show_person_role_assignments.assignable_id = ?) OR
                     EXISTS (SELECT 1 FROM show_person_role_assignments
                             WHERE show_person_role_assignments.show_id = shows.id
                             AND show_person_role_assignments.assignable_type = 'Group'
                             AND show_person_role_assignments.assignable_id IN (?))",
                    @person.id, group_ids.presence || [ 0 ], @person.id, group_ids.presence || [ 0 ]
                  )
                  .first!
      @production = @show.production
      @show_person_role_assignments = @show.show_person_role_assignments
                                           .includes(:role)
                                           .to_a

      # Preload polymorphic assignables with headshots
      ActiveRecord::Associations::Preloader.new(
        records: @show_person_role_assignments.select { |a| a.assignable_type == "Person" },
        associations: { assignable: { profile_headshots: { image_attachment: :blob } } }
      ).call
      ActiveRecord::Associations::Preloader.new(
        records: @show_person_role_assignments.select { |a| a.assignable_type == "Group" },
        associations: :assignable
      ).call

      # Get my assignment for this show (check both person and group assignments) - use preloaded group_ids
      @my_assignment = @show_person_role_assignments.find do |a|
        (a.assignable_type == "Person" && a.assignable_id == @person.id) ||
          (a.assignable_type == "Group" && group_ids.include?(a.assignable_id))
      end
    end

    def calendar
      @person = Current.user.person

      # Get groups the person is a member of
      @groups = @person.groups.active.order(:name).to_a
      group_ids = @groups.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all
      @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

      include_person = @entity_filter.include?("person")
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)

      # Determine date range for loading shows
      # Load from 6 months ago to 12 months in the future to support navigation
      start_date = 6.months.ago.beginning_of_month
      end_date = 12.months.from_now.end_of_month

      # Get all shows from selected entities with entity tracking
      shows_with_entities = {}

      # Add person shows if selected
      if include_person
        person_shows = Show.joins(production: { talent_pools: :people })
                           .where(people: { id: @person.id })
                           .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                           .where(canceled: false)
                           .includes(:production, :location)
                           .select("shows.*")
                           .distinct
                           .to_a
        person_shows.each do |show|
          shows_with_entities[show.id] ||= { show: show, entities: [] }
          shows_with_entities[show.id][:entities] << "person"
        end
      end

      # Add group shows in batch if selected
      if selected_group_ids.any?
        group_shows = Show.select("shows.*, groups.id as source_group_id")
                          .joins(production: { talent_pools: :groups })
                          .where(groups: { id: selected_group_ids })
                          .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                          .where(canceled: false)
                          .includes(:production, :location)
                          .distinct
                          .to_a
        group_shows.each do |show|
          group_id = show.read_attribute(:source_group_id)
          shows_with_entities[show.id] ||= { show: show, entities: [] }
          shows_with_entities[show.id][:entities] << "group_#{group_id}"
        end
      end

      # Extract just the shows and filter by event type
      @shows = shows_with_entities.values.map do |h|
        h[:show]
      end.select { |show| @event_type_filter.include?(show.event_type) }

      # Order shows
      @shows = @shows.sort_by(&:date_and_time)

      # Group shows by month
      @shows_by_month = @shows.group_by { |show| show.date_and_time.beginning_of_month }

      # Get assignments for these shows - use group_ids instead of pluck
      show_ids = @shows.map(&:id)
      assignments = ShowPersonRoleAssignment.where(show_id: show_ids)
                                            .where("(assignable_type = ? AND assignable_id = ?) OR (assignable_type = ? AND assignable_id IN (?))",
                                                   "Person", @person.id, "Group", group_ids)
                                            .to_a
      @assignments_by_show = assignments.index_by(&:show_id)

      # Build mapping of which entities have assignments for each show
      @show_assignments = {}
      assignments.each do |assignment|
        @show_assignments[assignment.show_id] ||= []
        if assignment.assignable_type == "Person" && assignment.assignable_id == @person.id
          @show_assignments[assignment.show_id] << { type: "person", entity: @person }
        elsif assignment.assignable_type == "Group"
          group = groups_by_id[assignment.assignable_id]
          @show_assignments[assignment.show_id] << { type: "group", entity: group } if group
        end
      end
    end
  end
end
