class My::DashboardController < ApplicationController
  def index
    # Check if user needs to see welcome page
    if Current.user.welcomed_at.nil?
      @show_my_sidebar = false
      render "welcome" and return
    end

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

  def welcome
    @show_my_sidebar = false
    render "welcome"
  end

  def dismiss_welcome
    Current.user.update(welcomed_at: Time.current)
    redirect_to my_dashboard_path
  end
end
