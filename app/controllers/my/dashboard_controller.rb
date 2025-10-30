class My::DashboardController < ApplicationController
  def index
    @productions = Production.joins(casts: [ :casts_people ]).where(casts_people: { person_id: Current.user.person.id }).distinct

    # 2) My next audition session
    @upcoming_audition_sessions = AuditionSession
      .joins(:auditions)
      .where(auditions: { person_id: Current.user.person.id })
      .where("audition_sessions.start_at >= ?", Time.current)
      .order("audition_sessions.start_at")
      .distinct

    # My audition requests for call to auditions that are still open
    @open_audition_requests = Current.user.person.audition_requests
      .joins(:call_to_audition)
      .where("call_to_auditions.closes_at >= ?", Time.current)
      .includes(:call_to_audition)
      .order("call_to_auditions.closes_at")
  end
end
