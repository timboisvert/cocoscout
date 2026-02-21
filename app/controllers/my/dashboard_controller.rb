# frozen_string_literal: true

module My
  class DashboardController < ApplicationController
    def index
      # Get all active profiles and their IDs
      @people = Current.user.people.active.order(:created_at).to_a
      @all_profiles = @people # alias for backward compatibility with view
      @person = Current.user.person # primary person for vacancy links
      people_ids = @people.map(&:id)
      people_by_id = @people.index_by(&:id)

      # Get groups from ALL profiles
      @groups = Group.active.joins(:group_memberships).where(group_memberships: { person_id: people_ids }).distinct.order(:name).to_a
      group_ids = @groups.map(&:id)
      groups_by_id = @groups.index_by(&:id)

      # Get productions where user is in the talent pool (own or shared)
      # Productions via own talent pool
      own_pool_production_ids = Production.joins(talent_pools: :people).where(people: { id: people_ids }).pluck(:id)
      # Productions via shared talent pool
      shared_pool_production_ids = Production.joins(talent_pool_shares: { talent_pool: :people }).where(people: { id: people_ids }).pluck(:id)
      @productions = Production.where(id: (own_pool_production_ids + shared_pool_production_ids).uniq)

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

      # Sign-up registrations for all profiles (exclude archived forms)
      @sign_up_registrations_by_show = Hash.new { |h, k| h[k] = [] }
      registrations = SignUpRegistration
        .where(person_id: people_ids)
        .where.not(status: "cancelled")
        .includes(
          :person,
          sign_up_slot: { sign_up_form_instance: :show, sign_up_form: {} },
          sign_up_form_instance: :show
        )
        .to_a

      registrations.each do |reg|
        # Skip if the sign-up form is archived
        form = reg.sign_up_slot&.sign_up_form
        next if form&.archived_at.present?

        show = reg.sign_up_slot&.sign_up_form_instance&.show || reg.sign_up_form_instance&.show
        next unless show && show.date_and_time >= Time.current && show.date_and_time <= end_date

        @sign_up_registrations_by_show[show.id] << reg
        show_data_by_id[show.id] ||= { show: show, assignments: [], sign_up_registrations: [] }
        show_data_by_id[show.id][:sign_up_registrations] ||= []
        show_data_by_id[show.id][:sign_up_registrations] << reg
      end

      @upcoming_show_rows = show_data_by_id.values.sort_by { |row| row[:show].date_and_time }

      # Load vacancies created by the user (they said they can't make it)
      # Used to show "You've indicated you can't make it" indicator
      # For non-linked shows, the person was removed from cast but we still want to show them
      upcoming_show_ids = @upcoming_show_rows.map { |row| row[:show].id }

      @my_vacancies_by_show = {}
      open_vacancies = RoleVacancy
        .where(vacated_by_type: "Person", vacated_by_id: people_ids)
        .where.not(status: [ :filled, :cancelled ])
        .includes(:show, :affected_shows, :role, :invitations)
        .to_a

      open_vacancies.each do |vacancy|
        # For non-linked shows, use the primary show_id
        # For linked shows, use affected_shows if present, otherwise fall back to show_id
        if vacancy.show.linked? && vacancy.affected_shows.any?
          vacancy.affected_shows.each do |affected_show|
            next unless upcoming_show_ids.include?(affected_show.id)
            @my_vacancies_by_show[affected_show.id] ||= []
            @my_vacancies_by_show[affected_show.id] << vacancy
          end
        else
          # Non-linked show, or linked show without affected_shows set
          @my_vacancies_by_show[vacancy.show_id] ||= []
          @my_vacancies_by_show[vacancy.show_id] << vacancy
        end
      end

      # Also include shows where user has an open vacancy but no assignment
      # (for non-linked events where they were removed from cast)
      vacancy_only_show_ids = @my_vacancies_by_show.keys - upcoming_show_ids
      if vacancy_only_show_ids.any?
        vacancy_shows = Show
          .where(id: vacancy_only_show_ids)
          .where("date_and_time >= ? AND date_and_time <= ?", Time.current, end_date)
          .includes(:production, :location, :event_linkage)
          .to_a

        vacancy_shows.each do |show|
          show_data_by_id[show.id] ||= { show: show, assignments: [], vacancy_only: true }
        end

        # Re-sort to include vacancy-only shows
        @upcoming_show_rows = show_data_by_id.values.sort_by { |row| row[:show].date_and_time }
      end

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
                                           entity: person, audition: audition }
        elsif audition.auditionable_type == "Group"
          group = groups_by_id[audition.auditionable_id]
          if group
            @upcoming_audition_entities << { audition_session: audition.audition_session, entity_type: "group",
                                             entity: group, audition: audition }
          end
        end
      end

      @upcoming_audition_entities = @upcoming_audition_entities.sort_by do |item|
        item[:audition_session].start_at
      end.first(5)

      # Unresolved vacancy invitations for all profiles (not claimed, vacancy still open)
      @pending_vacancy_invitations = RoleVacancyInvitation
                                      .unresolved
                                      .where(person_id: people_ids)
                                      .includes(role_vacancy: [ :role, { show: :production } ])
                                      .order("shows.date_and_time ASC")

      # Pending agreement signatures for productions where user is in talent pool
      # Find productions that require agreements but user hasn't signed
      @pending_agreements = @productions
        .select(&:agreement_required?)
        .reject { |production| production.agreement_signed_by?(@person) }
        .sort_by(&:name)
    end

    def dismiss_onboarding
      Current.user.people.active.update_all(profile_welcomed_at: Time.current)
      redirect_to my_dashboard_path
    end
  end
end
