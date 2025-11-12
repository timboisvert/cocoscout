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

    # My audition requests for audition cycles that are still open
    @open_audition_requests = Current.user.person.audition_requests
      .joins(:audition_cycle)
      .where("audition_cycles.closes_at >= ?", Time.current)
      .includes(:audition_cycle)
      .order("audition_cycles.closes_at")
  end
end
