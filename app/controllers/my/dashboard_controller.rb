class My::DashboardController < ApplicationController
  def index
    # Check if user needs to see welcome page (but not when impersonating)
    if Current.user.welcomed_at.nil? && session[:user_doing_the_impersonating].blank?
      @show_my_sidebar = false
      render "welcome" and return
    end

    @productions = Production.joins(talent_pools: :people).where(people: { id: Current.user.person.id }).distinct

    # Get upcoming shows where user has a role assignment (either directly or through a group)
    @upcoming_shows = Show
      .joins(:show_person_role_assignments)
      .where(show_person_role_assignments: { assignable_type: "Person", assignable_id: Current.user.person.id })
      .where("date_and_time >= ?", Time.current)
      .includes(:production, :location, show_person_role_assignments: :role)
      .order(:date_and_time)
      .limit(5)

    # 2) My next audition session
    @upcoming_audition_sessions = AuditionSession
      .joins(:auditions)
      .where(auditions: { auditionable_type: "Person", auditionable_id: Current.user.person.id })
      .where("audition_sessions.start_at >= ?", Time.current)
      .order(Arel.sql("audition_sessions.start_at"))
      .distinct

    # My audition requests for audition cycles that are still open
    @open_audition_requests = Current.user.person.audition_requests
      .joins(:audition_cycle)
      .where("audition_cycles.closes_at >= ? OR audition_cycles.closes_at IS NULL", Time.current)
      .includes(:audition_cycle)
      .order(Arel.sql("audition_cycles.closes_at ASC NULLS LAST"))

    # My pending questionnaires
    @pending_questionnaires = Current.user.person.all_invited_questionnaires
      .where(accepting_responses: true)
      .includes(:production, :questionnaire_responses)
      .order(created_at: :desc)
      .limit(5)
  end

  def welcome
    @show_my_sidebar = false
    render "welcome"
  end

  def dismiss_welcome
    # Prevent dismissing welcome screen when impersonating
    if session[:user_doing_the_impersonating].present?
      redirect_to my_dashboard_path, alert: "Cannot dismiss welcome screen while impersonating"
      return
    end

    Current.user.update(welcomed_at: Time.current)

    # If this is an AJAX request, just return success
    if request.xhr?
      head :ok
    else
      redirect_to my_dashboard_path
    end
  end
end
