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

      # ========================================
      # SCHEDULED AUDITIONS (have audition session)
      # ========================================
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

      # ========================================
      # AUDITION REQUESTS (pending, not yet scheduled)
      # ========================================
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

      @audition_requests = if requestable_conditions.any?
                             AuditionRequest
                               .active
                               .eager_load(audition_cycle: :production)
                               .where(requestable_conditions.join(" OR "), *requestable_params)
                               .to_a
      else
                             []
      end

      # Only show open audition requests (form reviewed, active)
      # Also filter out requests where casting was finalized more than 30 days ago
      thirty_days_ago = 30.days.ago
      @audition_requests = @audition_requests.select do |req|
        cycle = req.audition_cycle
        next false unless cycle.active && cycle.form_reviewed
        next false if cycle.closes_at.present? && cycle.closes_at <= Time.current

        # If casting was finalized more than 30 days ago, don't show
        if cycle.casting_finalized_at.present? && cycle.casting_finalized_at < thirty_days_ago
          next false
        end

        true
      end

      # Sort by closes_at (soonest first)
      @audition_requests = @audition_requests.sort_by do |req|
        req.audition_cycle.closes_at || Time.new(9999)
      end

      # Build audition request entities mapping for headshot display
      @audition_request_entities = {}
      @audition_requests.each do |audition_request|
        entities = []

        if audition_request.requestable_type == "Person" && selected_person_ids.include?(audition_request.requestable_id)
          person = people_by_id[audition_request.requestable_id]
          entities << { type: "person", entity: person } if person
        end

        if audition_request.requestable_type == "Group" && selected_group_ids.include?(audition_request.requestable_id)
          group = groups_by_id[audition_request.requestable_id]
          entities << { type: "group", entity: group } if group
        end

        @audition_request_entities[audition_request.id] = entities if entities.any?
      end
    end

    def show
      @audition = find_audition
      return redirect_to my_auditions_path, alert: "Audition not found" unless @audition

      @session = @audition.audition_session
      @cycle = @audition.audition_request.audition_cycle
      @production = @cycle.production
      @auditionable = @audition.auditionable
    end

    def accept
      @audition = find_audition
      return redirect_to my_auditions_path, alert: "Audition not found" unless @audition

      @audition.accept!
      redirect_to my_audition_path(@audition), notice: "You've confirmed your audition!"
    end

    def decline
      @audition = find_audition
      return redirect_to my_auditions_path, alert: "Audition not found" unless @audition

      @audition.decline!
      redirect_to my_audition_path(@audition), notice: "You've declined this audition."
    end

    private

    def find_audition
      # Find audition and verify user has access (owns the auditionable entity)
      audition = Audition.find_by(id: params[:id])
      return nil unless audition

      # Check if auditionable is a Person owned by current user
      if audition.auditionable_type == "Person"
        return audition if Current.user.people.where(id: audition.auditionable_id).exists?
      end

      # Check if auditionable is a Group the user is a member of
      if audition.auditionable_type == "Group"
        person_ids = Current.user.people.active.pluck(:id)
        return audition if GroupMembership.where(group_id: audition.auditionable_id, person_id: person_ids).exists?
      end

      nil
    end
  end
end
