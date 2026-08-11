# frozen_string_literal: true

module My
  class AvailabilityController < ApplicationController
    def calendar
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

      # Handle event type filter - checkboxes
      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all

      # Handle entity filter (person_ID, group_ID)
      default_entities = @people.map { |p| "person_#{p.id}" } + @groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity] ? params[:entity].split(",") : default_entities

      # Date range for calendar navigation (wider range to support month navigation)
      start_date = 6.months.ago.beginning_of_month
      end_date = 12.months.from_now.end_of_month

      # Build show_entity_pairs - array of { show:, entity_key:, entity: } hashes
      # This creates SEPARATE entries for each show/entity combination
      @show_entity_pairs = []

      selected_person_ids = @people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id)
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      # Add person shows if selected
      if selected_person_ids.any?
        # Person shows from direct talent pools
        person_shows = Show.joins(production: { talent_pools: :people })
                           .select("shows.*, people.id as source_person_id")
                           .where(people: { id: selected_person_ids })
                           .where.not(canceled: true)
                           .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                           .where.not(productions: { production_type: "course" })
                           .includes(:production, :location)
                           .order(:date_and_time)
                           .distinct
                           .to_a

        person_shows.each do |show|
          next unless @event_type_filter.include?(show.event_type)

          person_id = show.read_attribute(:source_person_id)
          person = people_by_id[person_id]
          @show_entity_pairs << {
            show: show,
            entity_key: "person_#{person_id}",
            entity: person
          } if person
        end

        # Person shows from shared talent pools
        shared_person_shows = Show.joins(production: { talent_pool_shares: { talent_pool: :people } })
                                  .select("shows.*, people.id as source_person_id")
                                  .where(people: { id: selected_person_ids })
                                  .where.not(canceled: true)
                                  .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                                  .where.not(productions: { production_type: "course" })
                                  .includes(:production, :location)
                                  .order(:date_and_time)
                                  .distinct
                                  .to_a

        shared_person_shows.each do |show|
          next unless @event_type_filter.include?(show.event_type)

          person_id = show.read_attribute(:source_person_id)
          person = people_by_id[person_id]
          # Only add if not already present
          unless @show_entity_pairs.any? { |item| item[:show].id == show.id && item[:entity_key] == "person_#{person_id}" }
            @show_entity_pairs << {
              show: show,
              entity_key: "person_#{person_id}",
              entity: person
            } if person
          end
        end
      end

      # Add group shows in batch if selected
      if selected_group_ids.any?
        # Group shows from direct talent pools
        group_shows = Show
                      .select("shows.*, groups.id as source_group_id")
                      .joins(production: { talent_pools: :groups })
                      .where(groups: { id: selected_group_ids })
                      .where.not(canceled: true)
                      .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                      .where.not(productions: { production_type: "course" })
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

        # Group shows from shared talent pools
        shared_group_shows = Show
                             .select("shows.*, groups.id as source_group_id")
                             .joins(production: { talent_pool_shares: { talent_pool: :groups } })
                             .where(groups: { id: selected_group_ids })
                             .where.not(canceled: true)
                             .where("date_and_time >= ? AND date_and_time <= ?", start_date, end_date)
                             .where.not(productions: { production_type: "course" })
                             .includes(:production, :location)
                             .order(:date_and_time)
                             .distinct
                             .to_a

        shared_group_shows.each do |show|
          next unless @event_type_filter.include?(show.event_type)

          group_id = show.read_attribute(:source_group_id)
          # Only add if not already present
          unless @show_entity_pairs.any? { |item| item[:show].id == show.id && item[:entity_key] == "group_#{group_id}" }
            @show_entity_pairs << {
              show: show,
              entity_key: "group_#{group_id}",
              entity: groups_by_id[group_id]
            }
          end
        end
      end

      # Filter out shows that have active sign-up forms (those go to Sign-Ups section, not availability)
      # This matches the logic in TaskListService
      all_collected_show_ids = @show_entity_pairs.map { |p| p[:show].id }.uniq
      shows_with_signup = SignUpFormInstance.joins(:sign_up_form)
                                            .where(show_id: all_collected_show_ids)
                                            .where(status: %w[scheduled open])
                                            .where(sign_up_forms: { archived_at: nil })
                                            .pluck(:show_id)
                                            .to_set
      @show_entity_pairs.reject! { |pair| shows_with_signup.include?(pair[:show].id) }

      # Sort by show date
      @show_entity_pairs.sort_by! { |pair| pair[:show].date_and_time }

      # Group by month using Date (not TimeWithZone) to avoid DST issues
      # TimeWithZone keys don't match across DST boundaries (e.g., -0600 vs -0500)
      @pairs_by_month = @show_entity_pairs.group_by { |pair| pair[:show].date_and_time.to_date.beginning_of_month }

      # Get availabilities for all entities in batch - indexed by [show_id, entity_key]
      all_show_ids = @show_entity_pairs.map { |p| p[:show].id }.uniq

      availability_conditions = []
      availability_params = []

      selected_person_ids.each do |pid|
        availability_conditions << "(available_entity_type = 'Person' AND available_entity_id = ?)"
        availability_params << pid
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
                       "person_#{availability.available_entity_id}"
        else
                       "group_#{availability.available_entity_id}"
        end
        @availabilities[[ availability.show_id, entity_key ]] = availability
      end
    end

    def update
      # Determine the entity based on entity_key parameter (now person_ID or group_ID format)
      entity_key = params[:entity_key]
      entity = resolve_entity_from_key(entity_key)

      return render json: { error: "Invalid entity" }, status: :unprocessable_entity unless entity

      @show = show_for_entity(entity, params[:show_id])

      @availability = ShowAvailability.find_or_initialize_by(available_entity: entity, show: @show)
      @availability.status = params[:status]
      @availability.note = params[:note] if params.key?(:note)
      if @availability.save
        render json: { status: @availability.status, note: @availability.note }
      else
        render json: { error: @availability.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another request created the record, so find and update it
      @availability = ShowAvailability.find_by!(available_entity: entity, show: @show)
      @availability.update!(status: params[:status])
      render json: { status: @availability.status, note: @availability.note }
    end

    def update_note
      entity_key = params[:entity_key]
      entity = resolve_entity_from_key(entity_key)

      return render json: { error: "Invalid entity" }, status: :unprocessable_entity unless entity

      @show = show_for_entity(entity, params[:show_id])

      @availability = ShowAvailability.find_by(available_entity: entity, show: @show)
      return render json: { error: "Not found" }, status: :not_found unless @availability

      if @availability.update(note: params[:note])
        render json: { status: @availability.status, note: @availability.note }
      else
        render json: { error: @availability.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    def update_audition_session
      # Determine the entity based on entity_key parameter (now person_ID or group_ID format)
      entity_key = params[:entity_key]
      entity = resolve_entity_from_key(entity_key)

      return render json: { error: "Invalid entity" }, status: :unprocessable_entity unless entity

      @session = AuditionSession.joins(audition_cycle: :production)
                                .where(productions: { organization_id: entity.organization_ids })
                                .find(params[:session_id])

      @availability = AuditionSessionAvailability.find_or_initialize_by(available_entity: entity, audition_session: @session)
      @availability.status = params[:status]
      if @availability.save
        render json: { status: @availability.status }
      else
        render json: { error: @availability.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another request created the record, so find and update it
      @availability = AuditionSessionAvailability.find_by!(available_entity: entity, audition_session: @session)
      @availability.update!(status: params[:status])
      render json: { status: @availability.status }
    end

    private

    # Availability may only be written against shows in organizations the
    # entity actually belongs to — unscoped finds let a user pollute any org's
    # availability data with their own rows.
    def show_for_entity(entity, show_id)
      Show.joins(:production)
          .where(productions: { organization_id: entity.organization_ids })
          .find(show_id)
    end

    def resolve_entity_from_key(entity_key)
      return nil unless entity_key

      if entity_key.start_with?("person_")
        # Extract person ID from "person_123" format
        person_id = entity_key.sub(/^person_/, "").to_i
        Current.user.people.find_by(id: person_id)
      elsif entity_key.start_with?("group_")
        # Extract group ID from "group_123" format
        group_id = entity_key.sub(/^group_/, "").to_i
        # Find group that any of the user's profiles is a member of
        people_ids = Current.user.people.pluck(:id)
        Group.joins(:group_memberships)
             .where(group_memberships: { person_id: people_ids })
             .find_by(id: group_id)
      elsif entity_key == "person"
        # Legacy support for old format
        Current.user.person
      else
        nil
      end
    end
  end
end
