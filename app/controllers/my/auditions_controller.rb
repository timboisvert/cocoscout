class My::AuditionsController < ApplicationController
  def index
    # Store the auditions filter
    @auditions_filter = (params[:auditions_filter] || session[:auditions_filter] || "all")
    session[:auditions_filter] = @auditions_filter

    # Store the audition requests_filter
    @requests_filter = (params[:requests_filter] || session[:requests_filter] || "all")
    session[:requests_filter] = @requests_filter

    # Get the auditions using the auditions filter
    @auditions = Current.user.person.auditions.includes(:audition_sessions, :audition_request)

    case @auditions_filter
    when "upcoming"
      @auditions = @auditions.where("audition_sessions.start_at > ?", Time.current).order("audition_sessions.start_at ASC").distinct
    when "past"
      @auditions = @auditions.where("audition_sessions.start_at <= ?", Time.current).order("audition_sessions.start_at DESC").distinct
    else
      @auditions_filter = "all"
      @auditions = @auditions.order("audition_sessions.start_at DESC").distinct
    end


    # Get the audition requests using the requests filter
    case @requests_filter
    when "open"
      @audition_requests = Current.user.person.audition_requests.eager_load(call_to_audition: :production).where("closes_at > ?", Time.current)
    else
      @requests_filter = "all"
      @audition_requests = Current.user.person.audition_requests.includes(call_to_audition: :production)
    end
  end
end
