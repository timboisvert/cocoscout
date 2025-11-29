class My::DashboardController < ApplicationController
  def index
    # Check if user needs to see welcome page (but not when impersonating)
    if Current.user.welcomed_at.nil? && session[:user_doing_the_impersonating].blank?
      @show_my_sidebar = false
      render "welcome" and return
    end

    @person = Current.user.person
    @groups = @person.groups.active.order(:name)

    @productions = Production.joins(talent_pools: :people).where(people: { id: Current.user.person.id }).distinct

    # Get upcoming shows where user or their groups have a role assignment
    group_ids = @groups.pluck(:id)
    @upcoming_show_entities = []

    # Person shows
    person_shows = Show
      .joins(:show_person_role_assignments)
      .where(show_person_role_assignments: { assignable_type: "Person", assignable_id: @person.id })
      .where("date_and_time >= ?", Time.current)
      .includes(:production, :location, show_person_role_assignments: :role)
      .order(:date_and_time)
      .limit(10)

    person_shows.each do |show|
      @upcoming_show_entities << { show: show, entity_type: "person", entity: @person }
    end

    # Group shows
    if group_ids.any?
      group_shows = Show
        .joins(:show_person_role_assignments)
        .where(show_person_role_assignments: { assignable_type: "Group", assignable_id: group_ids })
        .where("date_and_time >= ?", Time.current)
        .includes(:production, :location, show_person_role_assignments: :role)
        .order(:date_and_time)
        .limit(10)

      group_shows.each do |show|
        assignment = show.show_person_role_assignments.find { |a| a.assignable_type == "Group" && group_ids.include?(a.assignable_id) }
        group = @groups.find { |g| g.id == assignment.assignable_id }
        @upcoming_show_entities << { show: show, entity_type: "group", entity: group }
      end
    end

    @upcoming_show_entities = @upcoming_show_entities.sort_by { |item| item[:show].date_and_time }.first(5)

    # Upcoming audition sessions for person and groups
    @upcoming_audition_entities = []

    person_auditions = Audition
      .joins(:audition_session)
      .where(auditionable: @person)
      .where("audition_sessions.start_at >= ?", Time.current)
      .includes(audition_session: :production)
      .order(Arel.sql("audition_sessions.start_at"))
      .limit(10)

    person_auditions.each do |audition|
      @upcoming_audition_entities << { audition_session: audition.audition_session, entity_type: "person", entity: @person }
    end

    @groups.each do |group|
      group_auditions = Audition
        .joins(:audition_session)
        .where(auditionable: group)
        .where("audition_sessions.start_at >= ?", Time.current)
        .includes(audition_session: :production)
        .order(Arel.sql("audition_sessions.start_at"))
        .limit(10)

      group_auditions.each do |audition|
        @upcoming_audition_entities << { audition_session: audition.audition_session, entity_type: "group", entity: group }
      end
    end

    @upcoming_audition_entities = @upcoming_audition_entities.sort_by { |item| item[:audition_session].start_at }.first(5)

    # Audition requests for person and groups
    @open_audition_request_entities = []

    person_requests = AuditionRequest
      .joins(:audition_cycle)
      .where(requestable: @person)
      .where("audition_cycles.closes_at >= ? OR audition_cycles.closes_at IS NULL", Time.current)
      .includes(:audition_cycle)
      .order(Arel.sql("audition_cycles.closes_at ASC NULLS LAST"))
      .limit(10)

    person_requests.each do |request|
      @open_audition_request_entities << { audition_request: request, entity_type: "person", entity: @person }
    end

    @groups.each do |group|
      group_requests = AuditionRequest
        .joins(:audition_cycle)
        .where(requestable: group)
        .where("audition_cycles.closes_at >= ? OR audition_cycles.closes_at IS NULL", Time.current)
        .includes(:audition_cycle)
        .order(Arel.sql("audition_cycles.closes_at ASC NULLS LAST"))
        .limit(10)

      group_requests.each do |request|
        @open_audition_request_entities << { audition_request: request, entity_type: "group", entity: group }
      end
    end

    @open_audition_request_entities = @open_audition_request_entities.sort_by { |item| item[:audition_request].audition_cycle.closes_at || Time.new(9999) }.first(5)

    # Pending questionnaires for person and groups
    @pending_questionnaire_entities = []

    questionnaire_ids = []
    questionnaire_ids += QuestionnaireInvitation.where(invitee: @person).pluck(:questionnaire_id)
    @groups.each do |group|
      questionnaire_ids += QuestionnaireInvitation.where(invitee: group).pluck(:questionnaire_id)
    end

    questionnaires = Questionnaire
      .where(id: questionnaire_ids.uniq, accepting_responses: true, archived_at: nil)
      .includes(:production, :questionnaire_responses, :questionnaire_invitations)
      .order(created_at: :desc)

    questionnaires.each do |questionnaire|
      if questionnaire.questionnaire_invitations.exists?(invitee: @person)
        @pending_questionnaire_entities << { questionnaire: questionnaire, entity_type: "person", entity: @person }
      end

      @groups.each do |group|
        if questionnaire.questionnaire_invitations.exists?(invitee: group)
          @pending_questionnaire_entities << { questionnaire: questionnaire, entity_type: "group", entity: group }
        end
      end
    end

    @pending_questionnaire_entities = @pending_questionnaire_entities.first(5)
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
