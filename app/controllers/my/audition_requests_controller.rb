class My::AuditionRequestsController < ApplicationController
  def index
    @person = Current.user.person
    @groups = @person.groups.active.order(:name).to_a

    # Store the audition requests_filter
    @requests_filter = (params[:requests_filter] || session[:requests_filter] || "open")
    session[:requests_filter] = @requests_filter

    # Handle entity filter - comma-separated like availability
    @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

    include_person = @entity_filter.include?("person")
    selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)
    groups_by_id = @groups.index_by(&:id)

    # Build conditions for batch query
    requestable_conditions = []
    requestable_params = []

    if include_person
      requestable_conditions << "(requestable_type = 'Person' AND requestable_id = ?)"
      requestable_params << @person.id
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

      # Check if person has this audition request and is in entity filter
      if include_person && audition_request.requestable_type == "Person" && audition_request.requestable_id == @person.id
        entities << { type: "person", entity: @person }
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
