# frozen_string_literal: true

module My
  class ShowsController < ApplicationController
    def index
      @person = Current.user.person
      @people = Current.user.people.active.order(:created_at).to_a
      people_ids = @people.map(&:id)
      people_by_id = @people.index_by(&:id)

      # Get groups from all profiles
      @groups = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: people_ids })
                     .distinct
                     .order(:name)
                     .to_a
      group_ids = @groups.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      # Handle filter parameters
      @filter = params[:filter] || "my_assignments"
      @event_type_filter = params[:event_type].present? ? params[:event_type].split(",") : EventTypes.all
      default_entities = @people.map { |p| "person_#{p.id}" } + @groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity].present? ? params[:entity].split(",") : default_entities

      selected_person_ids = @people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id)
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)

      # Step 1: Get ALL shows from talent pool membership (base set for All Shows / By Production)
      all_talent_pool_show_ids = Set.new

      if selected_person_ids.any?
        tp_person_shows = Show.joins(production: { talent_pools: :people })
                              .where(people: { id: selected_person_ids })
                              .where("date_and_time >= ?", Time.current)
                              .pluck(:id)
        all_talent_pool_show_ids.merge(tp_person_shows)
      end

      if selected_group_ids.any?
        tp_group_shows = Show.joins(production: { talent_pools: :groups })
                             .where(groups: { id: selected_group_ids })
                             .where("date_and_time >= ?", Time.current)
                             .pluck(:id)
        all_talent_pool_show_ids.merge(tp_group_shows)
      end

      # Step 1b: Get shows where user has sign-up registrations
      sign_up_show_ids = Set.new
      @sign_up_registrations_by_show = Hash.new { |h, k| h[k] = [] }

      if selected_person_ids.any?
        # Get active registrations for the selected people
        registrations = SignUpRegistration
          .where(person_id: selected_person_ids)
          .where.not(status: "cancelled")
          .includes(
            :person,
            sign_up_slot: { sign_up_form_instance: :show },
            sign_up_form_instance: :show
          )
          .to_a

        registrations.each do |reg|
          # Get the show from either the slot's instance or the direct instance (queued)
          show = reg.sign_up_slot&.sign_up_form_instance&.show || reg.sign_up_form_instance&.show
          next unless show && show.date_and_time >= Time.current

          sign_up_show_ids << show.id
          @sign_up_registrations_by_show[show.id] << reg
        end
      end

      # Merge sign-up shows into the main set
      all_talent_pool_show_ids.merge(sign_up_show_ids)

      # Load all shows from talent pool with includes
      all_shows = Show.where(id: all_talent_pool_show_ids)
                      .includes(:production, :location, :event_linkage)
                      .order(:date_and_time)
                      .to_a

      # Filter by event type
      all_shows.select! { |show| @event_type_filter.include?(show.event_type) }

      # Step 2: Get all assignments for these shows (for selected people and groups)
      show_ids = all_shows.map(&:id)
      assignments = if show_ids.any?
        ShowPersonRoleAssignment
          .where(show_id: show_ids)
          .where(
            "(assignable_type = 'Person' AND assignable_id IN (?)) OR (assignable_type = 'Group' AND assignable_id IN (?))",
            selected_person_ids.presence || [ 0 ],
            selected_group_ids.presence || [ 0 ]
          )
          .includes(:role)
          .to_a
      else
        []
      end

      # Build assignments hash by show_id
      assignments_by_show = Hash.new { |h, k| h[k] = [] }
      assignments.each do |assignment|
        if assignment.assignable_type == "Person"
          person = people_by_id[assignment.assignable_id]
          assignments_by_show[assignment.show_id] << { type: "person", entity: person, assignment: assignment } if person
        elsif assignment.assignable_type == "Group"
          group = groups_by_id[assignment.assignable_id]
          assignments_by_show[assignment.show_id] << { type: "group", entity: group, assignment: assignment } if group
        end
      end

      # Step 3: Build show_data based on filter
      show_data_by_id = {}

      if @filter == "my_assignments"
        # Only include shows where the user has an assignment OR a sign-up registration
        all_shows.each do |show|
          show_assignments = assignments_by_show[show.id]
          show_sign_ups = @sign_up_registrations_by_show[show.id]
          next if show_assignments.empty? && show_sign_ups.empty?
          show_data_by_id[show.id] = {
            show: show,
            assignments: show_assignments,
            sign_up_registrations: show_sign_ups
          }
        end
      else
        # "all" or "by_production" - include all talent pool shows with their assignments (if any)
        all_shows.each do |show|
          show_data_by_id[show.id] = {
            show: show,
            assignments: assignments_by_show[show.id],
            sign_up_registrations: @sign_up_registrations_by_show[show.id]
          }
        end
      end

      # Check if user has ANY shows at all (before filtering) for showing filter bar
      @has_any_shows = all_talent_pool_show_ids.any?

      # Build @shows array
      @shows = show_data_by_id.values.map { |data| data[:show] }.sort_by(&:date_and_time)

      # Get productions from shows
      production_ids = @shows.map(&:production_id).uniq
      @productions = Production.where(id: production_ids).order(:name)

      # Build @show_assignments for compatibility
      @show_assignments = {}
      show_data_by_id.each do |show_id, data|
        @show_assignments[show_id] = data[:assignments]
      end

      # Build show entity rows for the view
      @show_entity_rows = show_data_by_id.values.sort_by { |row| row[:show].date_and_time }

      # Load vacancies created by the user (they said they can't make it)
      # For non-linked shows, the person was removed from cast but we still want to show them
      upcoming_show_ids = @shows.map(&:id)

      @my_vacancies_by_show = {}
      open_vacancies = RoleVacancy
        .where(vacated_by_type: "Person", vacated_by_id: people_ids)
        .where.not(status: [ :filled, :cancelled ])
        .includes(:show, :affected_shows, :role, :invitations)
        .to_a

      open_vacancies.each do |vacancy|
        # For non-linked shows, use the primary show_id
        # For linked shows, use affected_shows if present, otherwise fall back to show_id
        if vacancy.show.linked? && vacancy.affected_shows.any?
          vacancy.affected_shows.each do |affected_show|
            next unless upcoming_show_ids.include?(affected_show.id)
            @my_vacancies_by_show[affected_show.id] ||= []
            @my_vacancies_by_show[affected_show.id] << vacancy
          end
        else
          # Non-linked show, or linked show without affected_shows set
          @my_vacancies_by_show[vacancy.show_id] ||= []
          @my_vacancies_by_show[vacancy.show_id] << vacancy
        end
      end

      # Also include shows where user has an open vacancy but no assignment
      # (for non-linked events where they were removed from cast)
      vacancy_only_show_ids = @my_vacancies_by_show.keys - upcoming_show_ids
      if vacancy_only_show_ids.any? && @filter == "my_assignments"
        vacancy_shows = Show
          .where(id: vacancy_only_show_ids)
          .where("date_and_time >= ?", Time.current)
          .includes(:production, :location, :event_linkage)
          .to_a

        # Filter by event type
        vacancy_shows.select! { |show| @event_type_filter.include?(show.event_type) }

        vacancy_shows.each do |show|
          show_data_by_id[show.id] ||= { show: show, assignments: [], vacancy_only: true }
        end

        # Rebuild shows array and entity rows
        @shows = show_data_by_id.values.map { |data| data[:show] }.sort_by(&:date_and_time)
        @show_entity_rows = show_data_by_id.values.sort_by { |row| row[:show].date_and_time }
      end

      # Build @show_entities for compatibility
      @show_entities = {}
      @shows.each do |show|
        @show_entities[show.id] = show_data_by_id[show.id]&.[](:assignments) || []
      end

      # Unresolved vacancy invitations for all profiles (not claimed, vacancy still open)
      @pending_vacancy_invitations = RoleVacancyInvitation
                                      .unresolved
                                      .where(person_id: people_ids)
                                      .includes(role_vacancy: [ :role, { show: :production } ])
                                      .order("shows.date_and_time ASC")
    end

    def show
      @person = Current.user.person
      @people = Current.user.people.active.to_a
      people_ids = @people.map(&:id)

      # Get groups from all profiles
      @groups = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: people_ids })
                     .distinct
                     .to_a
      group_ids = @groups.map(&:id)

      # Find the show if user has access via:
      # 1. Any of user's profiles is in the production's talent pool
      # 2. Any of user's groups is in the production's talent pool
      # 3. Any of user's profiles has a direct role assignment
      # 4. Any of user's groups has a role assignment
      # 5. User has an open vacancy for this show (they can't make it but can reclaim)
      # 6. User has a sign-up registration for this show
      @show = Show.where(id: params[:id])
                  .includes(event_linkage: :shows)
                  .where(
                    "EXISTS (SELECT 1 FROM talent_pools
                             INNER JOIN talent_pool_memberships ON talent_pools.id = talent_pool_memberships.talent_pool_id
                             WHERE talent_pools.production_id = shows.production_id
                             AND talent_pool_memberships.member_type = 'Person'
                             AND talent_pool_memberships.member_id IN (?)) OR
                     EXISTS (SELECT 1 FROM talent_pools
                             INNER JOIN talent_pool_memberships ON talent_pools.id = talent_pool_memberships.talent_pool_id
                             WHERE talent_pools.production_id = shows.production_id
                             AND talent_pool_memberships.member_type = 'Group'
                             AND talent_pool_memberships.member_id IN (?)) OR
                     EXISTS (SELECT 1 FROM show_person_role_assignments
                             WHERE show_person_role_assignments.show_id = shows.id
                             AND show_person_role_assignments.assignable_type = 'Person'
                             AND show_person_role_assignments.assignable_id IN (?)) OR
                     EXISTS (SELECT 1 FROM show_person_role_assignments
                             WHERE show_person_role_assignments.show_id = shows.id
                             AND show_person_role_assignments.assignable_type = 'Group'
                             AND show_person_role_assignments.assignable_id IN (?)) OR
                     EXISTS (SELECT 1 FROM role_vacancies
                             WHERE role_vacancies.show_id = shows.id
                             AND role_vacancies.vacated_by_type = 'Person'
                             AND role_vacancies.vacated_by_id IN (?)
                             AND role_vacancies.status NOT IN ('filled', 'cancelled')) OR
                     EXISTS (SELECT 1 FROM sign_up_form_instances
                             INNER JOIN sign_up_slots ON sign_up_slots.sign_up_form_instance_id = sign_up_form_instances.id
                             INNER JOIN sign_up_registrations ON sign_up_registrations.sign_up_slot_id = sign_up_slots.id
                             WHERE sign_up_form_instances.show_id = shows.id
                             AND sign_up_registrations.person_id IN (?)
                             AND sign_up_registrations.status != 'cancelled') OR
                     EXISTS (SELECT 1 FROM sign_up_form_instances
                             INNER JOIN sign_up_registrations ON sign_up_registrations.sign_up_form_instance_id = sign_up_form_instances.id
                             WHERE sign_up_form_instances.show_id = shows.id
                             AND sign_up_registrations.person_id IN (?)
                             AND sign_up_registrations.status != 'cancelled')",
                    people_ids, group_ids.presence || [ 0 ], people_ids, group_ids.presence || [ 0 ], people_ids, people_ids, people_ids
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

      # Get my assignments for this show (check all profiles and group assignments)
      @my_assignments = @show_person_role_assignments.select do |a|
        (a.assignable_type == "Person" && people_ids.include?(a.assignable_id)) ||
          (a.assignable_type == "Group" && group_ids.include?(a.assignable_id))
      end

      # Load vacancies for this show created by the user's profiles
      # Used to show "You've indicated you can't make it" indicator
      # Check both primary show and affected_shows (for linked events)
      @my_vacancies = RoleVacancy
        .where(vacated_by_type: "Person", vacated_by_id: people_ids)
        .where.not(status: :filled)
        .where(
          "show_id = :show_id OR EXISTS (SELECT 1 FROM role_vacancy_shows WHERE role_vacancy_shows.role_vacancy_id = role_vacancies.id AND role_vacancy_shows.show_id = :show_id)",
          show_id: @show.id
        )
        .includes(:role)
        .to_a

      # Also include vacancies where a Group vacated (if user is in that group)
      @my_group_vacancies = RoleVacancy
        .where(vacated_by_type: "Group", vacated_by_id: group_ids)
        .where.not(status: :filled)
        .where(
          "show_id = :show_id OR EXISTS (SELECT 1 FROM role_vacancy_shows WHERE role_vacancy_shows.role_vacancy_id = role_vacancies.id AND role_vacancy_shows.show_id = :show_id)",
          show_id: @show.id
        )
        .includes(:role)
        .to_a

      # Build a lookup by [assignable_type, assignable_id] for quick access
      # Note: We don't include role_id because for linked events, each show has different role IDs
      # The vacancy affects ALL roles for that entity on the affected shows
      @vacancies_by_entity = {}
      (@my_vacancies + @my_group_vacancies).each do |vacancy|
        key = [ vacancy.vacated_by_type, vacancy.vacated_by_id ]
        @vacancies_by_entity[key] = vacancy
      end

      # Load sign-up registrations for this show
      @my_sign_up_registrations = SignUpRegistration
        .where(person_id: people_ids)
        .where.not(status: "cancelled")
        .joins("LEFT JOIN sign_up_slots ON sign_up_registrations.sign_up_slot_id = sign_up_slots.id")
        .joins("LEFT JOIN sign_up_form_instances AS slot_instances ON sign_up_slots.sign_up_form_instance_id = slot_instances.id")
        .joins("LEFT JOIN sign_up_form_instances AS direct_instances ON sign_up_registrations.sign_up_form_instance_id = direct_instances.id")
        .where("slot_instances.show_id = :show_id OR direct_instances.show_id = :show_id", show_id: @show.id)
        .includes(:person, sign_up_slot: { sign_up_form_instance: :sign_up_form })
        .to_a
    end

    def calendar
      @person = Current.user.person

      # Get groups the person is a member of
      @groups = @person.groups.active.order(:name).to_a
      group_ids = @groups.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all
      @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person_#{@person.id}" ] + @groups.map { |g| "group_#{g.id}" })

      include_person = @entity_filter.include?("person_#{@person.id}")
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

      # Add shows from sign-up registrations
      @sign_up_registrations_by_show = Hash.new { |h, k| h[k] = [] }
      if include_person
        registrations = SignUpRegistration
          .where(person_id: @person.id)
          .where.not(status: "cancelled")
          .includes(
            :person,
            sign_up_slot: { sign_up_form_instance: :show },
            sign_up_form_instance: :show
          )
          .to_a

        registrations.each do |reg|
          show = reg.sign_up_slot&.sign_up_form_instance&.show || reg.sign_up_form_instance&.show
          next unless show
          next unless show.date_and_time >= start_date && show.date_and_time <= end_date

          shows_with_entities[show.id] ||= { show: show, entities: [] }
          shows_with_entities[show.id][:entities] << "sign_up"
          @sign_up_registrations_by_show[show.id] << reg
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

    def reclaim_vacancy
      @show = Show.find(params[:show_id])
      @vacancy = RoleVacancy.find(params[:vacancy_id])

      # Verify the current user is the one who created the vacancy
      people_ids = Current.user.people.active.pluck(:id)
      group_ids = Group.active
                       .joins(:group_memberships)
                       .where(group_memberships: { person_id: people_ids })
                       .pluck(:id)

      can_reclaim = (@vacancy.vacated_by_type == "Person" && people_ids.include?(@vacancy.vacated_by_id)) ||
                    (@vacancy.vacated_by_type == "Group" && group_ids.include?(@vacancy.vacated_by_id))

      # User can reclaim if they own the vacancy and it's not already filled or cancelled
      # This includes: open, finding_replacement, and not_filling statuses
      is_reclaimable = !@vacancy.filled? && !@vacancy.cancelled?

      unless can_reclaim && is_reclaimable
        redirect_to my_show_path(@show), alert: "You cannot reclaim this vacancy."
        return
      end

      if @vacancy.reclaim!(by: Current.user)
        redirect_to my_show_path(@show), notice: "Great! You're back on the call sheet."
      else
        redirect_to my_show_path(@show), alert: "Unable to reclaim the vacancy."
      end
    end
  end
end
