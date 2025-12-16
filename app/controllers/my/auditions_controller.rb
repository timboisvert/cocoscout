# frozen_string_literal: true

module My
  class AuditionsController < ApplicationController
    def index
      @person = Current.user.person
      @groups = @person.groups.active.order(:name).to_a

      # Store the auditions filter (upcoming/past)
      @auditions_filter = params[:auditions_filter] || session[:auditions_filter] || "upcoming"
      session[:auditions_filter] = @auditions_filter

      # Handle entity filter - comma-separated like availability
      @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

      include_person = @entity_filter.include?("person")
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      # Build conditions for batch query
      auditionable_conditions = []
      auditionable_params = []

      if include_person
        auditionable_conditions << "(auditionable_type = 'Person' AND auditionable_id = ?)"
        auditionable_params << @person.id
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

        # Check if person has this audition and is in entity filter
        if include_person && audition.auditionable_type == "Person" && audition.auditionable_id == @person.id
          entities << { type: "person", entity: @person }
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
