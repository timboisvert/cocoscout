class My::AuditionRequestsController < ApplicationController
  def index
    @person = Current.user.person
    @groups = @person.groups.active.order(:name)

    # Store the audition requests_filter
    @requests_filter = (params[:requests_filter] || session[:requests_filter] || "open")
    session[:requests_filter] = @requests_filter

    # Handle entity filter - comma-separated like availability
    @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

    # Collect audition requests from selected entities
    all_audition_requests = []

    # Add person audition requests if selected
    if @entity_filter.include?("person")
      person_requests = AuditionRequest
        .eager_load(audition_cycle: :production)
        .where(requestable: @person)
      all_audition_requests += person_requests.to_a
    end

    # Add group audition requests if selected
    @groups.each do |group|
      if @entity_filter.include?("group_#{group.id}")
        group_requests = AuditionRequest
          .eager_load(audition_cycle: :production)
          .where(requestable: group)
        all_audition_requests += group_requests.to_a
      end
    end

    @audition_requests = all_audition_requests.uniq

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

    # Build audition request entities mapping for headshot display
    @audition_request_entities = {}
    @audition_requests.each do |audition_request|
      entities = []

      # Check if person has this audition request and is in entity filter
      if @entity_filter.include?("person") && audition_request.requestable_type == "Person" && audition_request.requestable_id == @person.id
        entities << { type: "person", entity: @person }
      end

      # Check groups
      @groups.each do |group|
        if @entity_filter.include?("group_#{group.id}") && audition_request.requestable_type == "Group" && audition_request.requestable_id == group.id
          entities << { type: "group", entity: group }
        end
      end

      @audition_request_entities[audition_request.id] = entities if entities.any?
    end
  end
end
