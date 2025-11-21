class My::AuditionsController < ApplicationController
  def index
    # Store the auditions filter (upcoming/past) and entity filter (all/personal/group)
    @auditions_filter = (params[:auditions_filter] || session[:auditions_filter] || "upcoming")
    @entity_filter = (params[:entity_filter] || session[:entity_filter] || "all")
    session[:auditions_filter] = @auditions_filter
    session[:entity_filter] = @entity_filter

    # Base query for person's auditions
    person_auditions = Current.user.person.auditions
      .includes(:audition_session, :audition_request)
      .joins(audition_request: :audition_cycle)
      .where(audition_cycles: { finalize_audition_invitations: true })

    # Get group auditions if needed
    if @entity_filter == "all"
      # Include both personal and all group auditions
      group_ids = Current.user.person.groups.pluck(:id)

      @auditions = Audition
        .includes(:audition_session, :audition_request)
        .joins(audition_request: :audition_cycle)
        .where(audition_cycles: { finalize_audition_invitations: true })
        .where(
          "auditions.person_id = ? OR (audition_requests.requestable_type = ? AND audition_requests.requestable_id IN (?))",
          Current.user.person.id,
          "Group",
          group_ids
        )
    elsif @entity_filter == "personal"
      @auditions = person_auditions
    elsif @entity_filter.start_with?("group_")
      # Filter by specific group
      group_id = @entity_filter.sub("group_", "").to_i
      @auditions = Audition
        .includes(:audition_session, :audition_request)
        .joins(audition_request: :audition_cycle)
        .where(audition_cycles: { finalize_audition_invitations: true })
        .where(audition_requests: { requestable_type: "Group", requestable_id: group_id })
    else
      @auditions = person_auditions
    end

    # Apply time filter
    case @auditions_filter
    when "past"
      @auditions = @auditions.where("audition_sessions.start_at <= ?", Time.current).order(Arel.sql("audition_sessions.start_at DESC")).distinct
    else
      @auditions_filter = "upcoming"
      @auditions = @auditions.where("audition_sessions.start_at > ?", Time.current).order(Arel.sql("audition_sessions.start_at ASC")).distinct
    end

    # Get user's groups for the filter dropdown
    @user_groups = Current.user.person.groups.where(archived_at: nil).order(:name)
  end
end
