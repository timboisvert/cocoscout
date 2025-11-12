class My::AuditionsController < ApplicationController
  def index
    # Store the auditions filter
    @auditions_filter = (params[:auditions_filter] || session[:auditions_filter] || "upcoming")
    session[:auditions_filter] = @auditions_filter

    # Get the auditions using the auditions filter
    # Only show auditions where invitations have been finalized
    @auditions = Current.user.person.auditions
      .includes(:audition_session, :audition_request)
      .joins(audition_request: :audition_cycle)
      .where(audition_cycles: { finalize_audition_invitations: true })

    case @auditions_filter
    when "past"
      @auditions = @auditions.where("audition_sessions.start_at <= ?", Time.current).order("audition_sessions.start_at DESC").distinct
    else
      @auditions_filter = "upcoming"
      @auditions = @auditions.where("audition_sessions.start_at > ?", Time.current).order("audition_sessions.start_at ASC").distinct
    end
  end
end
