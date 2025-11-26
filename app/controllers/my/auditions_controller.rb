class My::AuditionsController < ApplicationController
  def index
    @person = Current.user.person
    @groups = @person.groups.active.order(:name)

    # Store the auditions filter (upcoming/past)
    @auditions_filter = (params[:auditions_filter] || session[:auditions_filter] || "upcoming")
    session[:auditions_filter] = @auditions_filter

    # Handle entity filter - comma-separated like availability
    @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

    # Collect auditions from selected entities
    all_auditions = []

    # Add person auditions if selected
    if @entity_filter.include?("person")
      person_auditions = Audition
        .includes(:audition_session, :audition_request)
        .joins(audition_request: :audition_cycle)
        .where(audition_cycles: { finalize_audition_invitations: true })
        .where(auditionable: @person)
      all_auditions += person_auditions.to_a
    end

    # Add group auditions if selected
    @groups.each do |group|
      if @entity_filter.include?("group_#{group.id}")
        group_auditions = Audition
          .includes(:audition_session, :audition_request)
          .joins(audition_request: :audition_cycle)
          .where(audition_cycles: { finalize_audition_invitations: true })
          .where(auditionable: group)
        all_auditions += group_auditions.to_a
      end
    end

    @auditions = all_auditions.uniq

    @auditions = all_auditions.uniq

    # Apply time filter
    case @auditions_filter
    when "past"
      @auditions = @auditions.select { |a| a.audition_session.start_at <= Time.current }.sort_by { |a| a.audition_session.start_at }.reverse
    else
      @auditions_filter = "upcoming"
      @auditions = @auditions.select { |a| a.audition_session.start_at > Time.current }.sort_by { |a| a.audition_session.start_at }
    end

    # Build audition entities mapping for headshot display
    @audition_entities = {}
    @auditions.each do |audition|
      entities = []

      # Check if person has this audition and is in entity filter
      if @entity_filter.include?("person") && audition.auditionable_type == "Person" && audition.auditionable_id == @person.id
        entities << { type: "person", entity: @person }
      end

      # Check groups
      @groups.each do |group|
        if @entity_filter.include?("group_#{group.id}") && audition.auditionable_type == "Group" && audition.auditionable_id == group.id
          entities << { type: "group", entity: group }
        end
      end

      @audition_entities[audition.id] = entities if entities.any?
    end
  end
end
