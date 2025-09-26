class My::AuditionRequestsController < ApplicationController
  def index
    # Store the audition requests_filter
    @requests_filter = (params[:requests_filter] || session[:requests_filter] || "all")
    session[:requests_filter] = @requests_filter

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
