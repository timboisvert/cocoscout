# frozen_string_literal: true

module My
  class DashboardController < ApplicationController
    def index
      # Check if user needs to see welcome page (but not when impersonating)
      if Current.user.welcomed_at.nil? && session[:user_doing_the_impersonating].blank?
        @show_my_sidebar = false
        render "welcome" and return
      end

      @person = Current.user.person
      @groups = @person.groups.active.order(:name).to_a
      group_ids = @groups.map(&:id)

      @productions = Production.joins(talent_pools: :people).where(people: { id: Current.user.person.id }).distinct

      # Get upcoming shows where user or their groups have a role assignment (next 45 days)
      # Consolidate by show - one row per show with all entity assignments
      end_date = 45.days.from_now
      show_data_by_id = {}

      # Person shows
      person_shows = Show
                     .joins(:show_person_role_assignments)
                     .where(show_person_role_assignments: { assignable_type: "Person", assignable_id: @person.id })
                     .where("date_and_time >= ? AND date_and_time <= ?", Time.current, end_date)
                     .includes(:production, :location, show_person_role_assignments: :role)
                     .order(:date_and_time)

      person_shows.each do |show|
        assignment = show.show_person_role_assignments.find { |a| a.assignable_type == "Person" && a.assignable_id == @person.id }
        if assignment
          show_data_by_id[show.id] ||= { show: show, assignments: [] }
          show_data_by_id[show.id][:assignments] << { type: "person", entity: @person, assignment: assignment }
        end
      end

      # Group shows
      if group_ids.any?
        group_shows = Show
                      .joins(:show_person_role_assignments)
                      .where(show_person_role_assignments: { assignable_type: "Group", assignable_id: group_ids })
                      .where("date_and_time >= ? AND date_and_time <= ?", Time.current, end_date)
                      .includes(:production, :location, show_person_role_assignments: :role)
                      .order(:date_and_time)

        # Build groups_by_id lookup for O(1) access
        groups_by_id = @groups.index_by(&:id)

        group_shows.each do |show|
          assignment = show.show_person_role_assignments.find do |a|
            a.assignable_type == "Group" && group_ids.include?(a.assignable_id)
          end
          if assignment
            group = groups_by_id[assignment.assignable_id]
            show_data_by_id[show.id] ||= { show: show, assignments: [] }
            show_data_by_id[show.id][:assignments] << { type: "group", entity: group, assignment: assignment }
          end
        end
      end

      @upcoming_show_rows = show_data_by_id.values.sort_by { |row| row[:show].date_and_time }

      # Upcoming audition sessions for person and groups - batch query
      @upcoming_audition_entities = []

      # Build list of auditionable entities for batch query
      auditionable_conditions = [ [ @person.class.name, @person.id ] ]
      @groups.each { |g| auditionable_conditions << [ g.class.name, g.id ] }

      all_auditions = Audition
                      .joins(:audition_session)
                      .where("audition_sessions.start_at >= ?", Time.current)
                      .where(
                        auditionable_conditions.map { "(auditionable_type = ? AND auditionable_id = ?)" }.join(" OR "),
                        *auditionable_conditions.flatten
                      )
                      .includes(audition_session: :production)
                      .order(Arel.sql("audition_sessions.start_at"))
                      .limit(20)
                      .to_a

      groups_by_id = @groups.index_by(&:id)
      all_auditions.each do |audition|
        if audition.auditionable_type == "Person" && audition.auditionable_id == @person.id
          @upcoming_audition_entities << { audition_session: audition.audition_session, entity_type: "person",
                                           entity: @person }
        elsif audition.auditionable_type == "Group"
          group = groups_by_id[audition.auditionable_id]
          if group
            @upcoming_audition_entities << { audition_session: audition.audition_session, entity_type: "group",
                                             entity: group }
          end
        end
      end

      @upcoming_audition_entities = @upcoming_audition_entities.sort_by do |item|
        item[:audition_session].start_at
      end.first(5)

      # Audition requests for person and groups - batch query
      @open_audition_request_entities = []

      all_requests = AuditionRequest
                     .joins(:audition_cycle)
                     .where("audition_cycles.closes_at >= ? OR audition_cycles.closes_at IS NULL", Time.current)
                     .where(
                       auditionable_conditions.map { "(requestable_type = ? AND requestable_id = ?)" }.join(" OR "),
                       *auditionable_conditions.flatten
                     )
                     .includes(:audition_cycle)
                     .order(Arel.sql("audition_cycles.closes_at ASC NULLS LAST"))
                     .limit(20)
                     .to_a

      all_requests.each do |request|
        if request.requestable_type == "Person" && request.requestable_id == @person.id
          @open_audition_request_entities << { audition_request: request, entity_type: "person", entity: @person }
        elsif request.requestable_type == "Group"
          group = groups_by_id[request.requestable_id]
          @open_audition_request_entities << { audition_request: request, entity_type: "group", entity: group } if group
        end
      end

      @open_audition_request_entities = @open_audition_request_entities.sort_by do |item|
        item[:audition_request].audition_cycle.closes_at || Time.new(9999)
      end.first(5)

      # Pending questionnaires for person and groups - batch query
      @pending_questionnaire_entities = []

      # Get all questionnaire IDs in one query
      invitee_conditions = [ [ "Person", @person.id ] ]
      @groups.each { |g| invitee_conditions << [ "Group", g.id ] }

      questionnaire_ids = QuestionnaireInvitation
                          .where(
                            invitee_conditions.map { "(invitee_type = ? AND invitee_id = ?)" }.join(" OR "),
                            *invitee_conditions.flatten
                          )
                          .pluck(:questionnaire_id)
                          .uniq

      questionnaires = Questionnaire
                       .where(id: questionnaire_ids, accepting_responses: true, archived_at: nil)
                       .includes(:production, :questionnaire_responses, :questionnaire_invitations)
                       .order(created_at: :desc)
                       .to_a

      # Build lookup of invitations by questionnaire
      questionnaires.each do |questionnaire|
        invitations = questionnaire.questionnaire_invitations.to_a

        # Check person invitation using in-memory filter
        if invitations.any? { |inv| inv.invitee_type == "Person" && inv.invitee_id == @person.id }
          @pending_questionnaire_entities << { questionnaire: questionnaire, entity_type: "person", entity: @person }
        end

        # Check group invitations using in-memory filter
        @groups.each do |group|
          if invitations.any? { |inv| inv.invitee_type == "Group" && inv.invitee_id == group.id }
            @pending_questionnaire_entities << { questionnaire: questionnaire, entity_type: "group", entity: group }
          end
        end
      end

      @pending_questionnaire_entities = @pending_questionnaire_entities.first(5)

      # Unresolved vacancy invitations for the person (not claimed, vacancy still open)
      @pending_vacancy_invitations = RoleVacancyInvitation
                                      .unresolved
                                      .where(person: @person)
                                      .includes(role_vacancy: [ :role, { show: :production } ])
                                      .order("shows.date_and_time ASC")
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
end
