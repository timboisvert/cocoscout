class My::AuditionsController < ApplicationController
  def index
    @audition_requests = Current.user.person.audition_requests.includes(call_to_audition: [ :production ])
    @auditions = Audition
        .where(person: Current.user.person)
        .joins(:audition_sessions)
        .includes(:audition_sessions, :audition_request)
        .distinct
  end
end
