# frozen_string_literal: true

module My
  class DashboardController < ApplicationController
    def index
      # Check if user needs to see welcome page (but not when impersonating)
      if Current.user.welcomed_at.nil? && session[:user_doing_the_impersonating].blank?
        @show_my_sidebar = false
        render "welcome" and return
      end

      # Get all active profiles and their IDs
      @people = Current.user.people.active.order(:created_at).to_a
      @all_profiles = @people # alias for backward compatibility with view
      people_ids = @people.map(&:id)
      people_by_id = @people.index_by(&:id)

      # Get groups from ALL profiles
      @groups = Group.active.joins(:group_memberships).where(group_memberships: { person_id: people_ids }).distinct.order(:name).to_a
      group_ids = @groups.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      @productions = Production.joins(talent_pools: :people).where(people: { id: people_ids }).distinct

      # Get upcoming shows where any profile or their groups have a role assignment (next 45 days)
      # Consolidate by show - one row per show with all entity assignments
      end_date = 45.days.from_now
      show_data_by_id = {}
      added_assignments = Set.new

      # Person shows (all profiles)
      person_shows = Show
                     .joins(:show_person_role_assignments)
                     .where(show_person_role_assignments: { assignable_type: "Person", assignable_id: people_ids })
                     .where("date_and_time >= ? AND date_and_time <= ?", Time.current, end_date)
                     .includes(:production, :location, :event_linkage, show_person_role_assignments: :role)
                     .order(:date_and_time)
                     .distinct

      person_shows.each do |show|
        show.show_person_role_assignments.each do |assignment|
          next unless assignment.assignable_type == "Person" && people_ids.include?(assignment.assignable_id)
          # Avoid duplicates by tracking assignment IDs
          next if added_assignments.include?(assignment.id)
          added_assignments.add(assignment.id)
          person = people_by_id[assignment.assignable_id]
          show_data_by_id[show.id] ||= { show: show, assignments: [] }
          show_data_by_id[show.id][:assignments] << { type: "person", entity: person, assignment: assignment }
        end
      end

      # Group shows
      if group_ids.any?
        group_shows = Show
                      .joins(:show_person_role_assignments)
                      .where(show_person_role_assignments: { assignable_type: "Group", assignable_id: group_ids })
                      .where("date_and_time >= ? AND date_and_time <= ?", Time.current, end_date)
                      .includes(:production, :location, :event_linkage, show_person_role_assignments: :role)
                      .order(:date_and_time)
                      .distinct

        group_shows.each do |show|
          show.show_person_role_assignments.each do |assignment|
            next unless assignment.assignable_type == "Group" && group_ids.include?(assignment.assignable_id)
            # Avoid duplicates by tracking assignment IDs
            next if added_assignments.include?(assignment.id)
            added_assignments.add(assignment.id)
            group = groups_by_id[assignment.assignable_id]
            show_data_by_id[show.id] ||= { show: show, assignments: [] }
            show_data_by_id[show.id][:assignments] << { type: "group", entity: group, assignment: assignment }
          end
        end
      end

      @upcoming_show_rows = show_data_by_id.values.sort_by { |row| row[:show].date_and_time }

      # Upcoming audition sessions for person and groups - batch query
      @upcoming_audition_entities = []

      # Build list of auditionable entities for batch query (all profiles + all groups)
      auditionable_conditions = @people.map { |p| [ p.class.name, p.id ] }
      @groups.each { |g| auditionable_conditions << [ g.class.name, g.id ] }

      all_auditions = Audition
                      .joins(:audition_session)
                      .joins(audition_request: :audition_cycle)
                      .where(audition_cycles: { finalize_audition_invitations: true })
                      .where("audition_sessions.start_at >= ?", Time.current)
                      .where(
                        auditionable_conditions.map { "(auditionable_type = ? AND auditionable_id = ?)" }.join(" OR "),
                        *auditionable_conditions.flatten
                      )
                      .includes(audition_session: :production)
                      .order(Arel.sql("audition_sessions.start_at"))
                      .limit(20)
                      .to_a

      all_auditions.each do |audition|
        if audition.auditionable_type == "Person" && people_ids.include?(audition.auditionable_id)
          person = people_by_id[audition.auditionable_id]
          @upcoming_audition_entities << { audition_session: audition.audition_session, entity_type: "person",
                                           entity: person }
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
                     .where(audition_cycles: { active: true, form_reviewed: true })
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
        if request.requestable_type == "Person" && people_ids.include?(request.requestable_id)
          person = people_by_id[request.requestable_id]
          @open_audition_request_entities << { audition_request: request, entity_type: "person", entity: person }
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

      # Get all questionnaire IDs in one query (all profiles + all groups)
      invitee_conditions = @people.map { |p| [ "Person", p.id ] }
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

        # Check person invitations using in-memory filter (all profiles)
        @people.each do |person|
          if invitations.any? { |inv| inv.invitee_type == "Person" && inv.invitee_id == person.id }
            @pending_questionnaire_entities << { questionnaire: questionnaire, entity_type: "person", entity: person }
          end
        end

        # Check group invitations using in-memory filter
        @groups.each do |group|
          if invitations.any? { |inv| inv.invitee_type == "Group" && inv.invitee_id == group.id }
            @pending_questionnaire_entities << { questionnaire: questionnaire, entity_type: "group", entity: group }
          end
        end
      end

      @pending_questionnaire_entities = @pending_questionnaire_entities.first(5)

      # Unresolved vacancy invitations for all profiles (not claimed, vacancy still open)
      @pending_vacancy_invitations = RoleVacancyInvitation
                                      .unresolved
                                      .where(person_id: people_ids)
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
