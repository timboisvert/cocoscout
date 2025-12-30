# frozen_string_literal: true

module My
  class AuditionsController < ApplicationController
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

      # Store the auditions filter (upcoming/past) - always default to upcoming
      @auditions_filter = params[:auditions_filter].presence || "upcoming"

      # Handle entity filter - now uses person_ID format
      default_entities = @people.map { |p| "person_#{p.id}" } + @groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity] ? params[:entity].split(",") : default_entities

      selected_person_ids = @people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id)
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      # Build conditions for batch query
      auditionable_conditions = []
      auditionable_params = []

      if selected_person_ids.any?
        auditionable_conditions << "(auditionable_type = 'Person' AND auditionable_id IN (?))"
        auditionable_params << selected_person_ids
      end

      if selected_group_ids.any?
        auditionable_conditions << "(auditionable_type = 'Group' AND auditionable_id IN (?))"
        auditionable_params << selected_group_ids
      end

      # Batch query for all auditions
      @auditions = if auditionable_conditions.any?
                     Audition
                       .includes(:audition_session, :audition_request)
                       .joins(audition_request: :audition_cycle)
                       .where(audition_cycles: { finalize_audition_invitations: true })
                       .where(auditionable_conditions.join(" OR "), *auditionable_params)
                       .to_a
      else
                     []
      end

      # Apply time filter - filter out auditions without sessions first
      @auditions = @auditions.select { |a| a.audition_session.present? }

      case @auditions_filter
      when "past"
        @auditions = @auditions.select do |a|
          a.audition_session.start_at <= Time.current
        end.sort_by { |a| a.audition_session.start_at }.reverse
      else
        @auditions_filter = "upcoming"
        @auditions = @auditions.select do |a|
          a.audition_session.start_at >= Time.current
        end.sort_by { |a| a.audition_session.start_at }
      end

      # Build audition entities mapping for headshot display using preloaded data
      @audition_entities = {}
      @auditions.each do |audition|
        entities = []

        # Check if any person profile has this audition and is in entity filter
        if audition.auditionable_type == "Person" && selected_person_ids.include?(audition.auditionable_id)
          person = people_by_id[audition.auditionable_id]
          entities << { type: "person", entity: person } if person
        end

        # Check groups using preloaded data
        if audition.auditionable_type == "Group" && selected_group_ids.include?(audition.auditionable_id)
          group = groups_by_id[audition.auditionable_id]
          entities << { type: "group", entity: group } if group
        end

        @audition_entities[audition.id] = entities if entities.any?
      end
    end
  end
end
