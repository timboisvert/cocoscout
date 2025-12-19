# frozen_string_literal: true

module My
  class AuditionRequestsController < ApplicationController
    def index
      @person = Current.user.person
      @people = Current.user.people.active.order(:created_at).to_a

      # Get all groups from all profiles
      @groups = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: @people.map(&:id) })
                     .distinct
                     .order(:name)
                     .to_a

      # Store the audition requests_filter
      @requests_filter = params[:requests_filter] || session[:requests_filter] || "open"
      session[:requests_filter] = @requests_filter

      # Handle entity filter - comma-separated, now uses person_ID format
      default_entities = @people.map { |p| "person_#{p.id}" } + @groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity] ? params[:entity].split(",") : default_entities

      # Parse selected person IDs and group IDs from entity filter
      selected_person_ids = @people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id)
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)

      people_by_id = @people.index_by(&:id)
      groups_by_id = @groups.index_by(&:id)

      # Build conditions for batch query
      requestable_conditions = []
      requestable_params = []

      if selected_person_ids.any?
        requestable_conditions << "(requestable_type = 'Person' AND requestable_id IN (?))"
        requestable_params << selected_person_ids
      end

      if selected_group_ids.any?
        requestable_conditions << "(requestable_type = 'Group' AND requestable_id IN (?))"
        requestable_params << selected_group_ids
      end

      # Batch query for all audition requests
      @audition_requests = if requestable_conditions.any?
                             AuditionRequest
                               .eager_load(audition_cycle: :production)
                               .where(requestable_conditions.join(" OR "), *requestable_params)
                               .to_a
      else
                             []
      end

      # Apply filter
      case @requests_filter
      when "open"
        # Open means: active (not archived), form reviewed, and closes_at is in the future or nil (open-ended)
        @audition_requests = @audition_requests.select do |req|
          req.audition_cycle.active &&
            req.audition_cycle.form_reviewed &&
            (req.audition_cycle.closes_at.nil? || req.audition_cycle.closes_at > Time.current)
        end
      else
        @requests_filter = "all"
      end

      @audition_requests = @audition_requests.sort_by do |req|
        req.audition_cycle.closes_at || Time.new(9999)
      end

      # Build audition request entities mapping for headshot display using preloaded data
      @audition_request_entities = {}
      @audition_requests.each do |audition_request|
        entities = []

        # Check if any person profile has this audition request and is in entity filter
        if audition_request.requestable_type == "Person" && selected_person_ids.include?(audition_request.requestable_id)
          person = people_by_id[audition_request.requestable_id]
          entities << { type: "person", entity: person } if person
        end

        # Check groups using preloaded data
        if audition_request.requestable_type == "Group" && selected_group_ids.include?(audition_request.requestable_id)
          group = groups_by_id[audition_request.requestable_id]
          entities << { type: "group", entity: group } if group
        end

        @audition_request_entities[audition_request.id] = entities if entities.any?
      end
    end
  end
end
