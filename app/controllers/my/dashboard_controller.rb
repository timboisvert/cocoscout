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
      own_pool_production_ids = Production.joins(talent_pools: :people).where(people: { id: people_ids }).pluck(:id)
      shared_pool_production_ids = Production.joins(talent_pool_shares: { talent_pool: :people }).where(people: { id: people_ids }).pluck(:id)
      @productions = Production.where(id: (own_pool_production_ids + shared_pool_production_ids).uniq)

      # === Calendar data ===
      # Determine month to display
      @current_month = params[:month] ? Date.parse(params[:month]).in_time_zone.beginning_of_month : Time.current.beginning_of_month
      cal_start = 6.months.ago.beginning_of_month
      cal_end = 12.months.from_now.end_of_month
      prev_month = @current_month - 1.month
      next_month = @current_month + 1.month
      @can_go_prev = prev_month >= Time.current.beginning_of_month
      @can_go_next = next_month <= cal_end
      @prev_month = prev_month
      @next_month = next_month

      # === Filter parameters ===
      all_calendar_types = %w[show rehearsal meeting course audition]
      @event_type_filter = params[:event_type].present? ? params[:event_type].split(",") : all_calendar_types
      default_entities = @people.map { |p| "person_#{p.id}" } + @groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity].present? ? params[:entity].split(",") : default_entities

      selected_person_ids = @people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id)
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)

      # Unified calendar events: array of hashes with { date:, time:, title:, subtitle:, path:, type:, color: }
      @calendar_events = []

      # Map show event_types to calendar categories
      show_event_types = []
      show_event_types += %w[show class workshop open_mic] if @event_type_filter.include?("show")
      show_event_types += %w[rehearsal] if @event_type_filter.include?("rehearsal")
      show_event_types += %w[meeting] if @event_type_filter.include?("meeting")

      # --- Shows (from talent pools, both own and shared) ---
      show_data_by_id = {}

      if show_event_types.any? && selected_person_ids.any?
        person_shows = Show
          .joins(production: { talent_pools: :people })
          .where(people: { id: selected_person_ids })
          .where("date_and_time >= ? AND date_and_time <= ?", cal_start, cal_end)
          .where(canceled: false)
          .where.not(productions: { production_type: "course" })
          .where(event_type: show_event_types)
          .includes(:production, :location, show_person_role_assignments: :role)
          .distinct.to_a

        shared_person_shows = Show
          .joins(production: { talent_pool_shares: { talent_pool: :people } })
          .where(people: { id: selected_person_ids })
          .where("date_and_time >= ? AND date_and_time <= ?", cal_start, cal_end)
          .where(canceled: false)
          .where.not(productions: { production_type: "course" })
          .where(event_type: show_event_types)
          .includes(:production, :location, show_person_role_assignments: :role)
          .distinct.to_a

        (person_shows + shared_person_shows).uniq(&:id).each do |show|
          show_data_by_id[show.id] = show
          role_name = show.show_person_role_assignments
            .detect { |a| a.assignable_type == "Person" && selected_person_ids.include?(a.assignable_id) }
            &.role&.name

          color = case show.event_type
                  when "rehearsal" then "blue"
                  when "meeting" then "green"
                  else "pink"
          end

          @calendar_events << {
            date: show.date_and_time.to_date,
            time: show.date_and_time,
            title: show.production.name,
            subtitle: role_name || show.event_type.titleize,
            path: my_show_path(show),
            type: :show,
            color: color,
            event_type: show.event_type
          }
        end
      end

      # Group shows
      if show_event_types.any? && selected_group_ids.any?
        group_shows = Show
          .joins(production: { talent_pools: :groups })
          .where(groups: { id: selected_group_ids })
          .where("date_and_time >= ? AND date_and_time <= ?", cal_start, cal_end)
          .where(canceled: false)
          .where.not(productions: { production_type: "course" })
          .where(event_type: show_event_types)
          .includes(:production, :location, show_person_role_assignments: :role)
          .distinct.to_a

        shared_group_shows = Show
          .joins(production: { talent_pool_shares: { talent_pool: :groups } })
          .where(groups: { id: selected_group_ids })
          .where("date_and_time >= ? AND date_and_time <= ?", cal_start, cal_end)
          .where(canceled: false)
          .where.not(productions: { production_type: "course" })
          .where(event_type: show_event_types)
          .includes(:production, :location, show_person_role_assignments: :role)
          .distinct.to_a

        (group_shows + shared_group_shows).uniq(&:id).each do |show|
          next if show_data_by_id[show.id] # Already added from person shows

          role_name = show.show_person_role_assignments
            .detect { |a| a.assignable_type == "Group" && selected_group_ids.include?(a.assignable_id) }
            &.role&.name

          color = case show.event_type
                  when "rehearsal" then "blue"
                  when "meeting" then "green"
                  else "pink"
          end

          @calendar_events << {
            date: show.date_and_time.to_date,
            time: show.date_and_time,
            title: show.production.name,
            subtitle: role_name || show.event_type.titleize,
            path: my_show_path(show),
            type: :show,
            color: color,
            event_type: show.event_type
          }
        end
      end

      # --- Course sessions ---
      if @event_type_filter.include?("course") && selected_person_ids.any?
        course_registrations = CourseRegistration
          .confirmed
          .where(person_id: selected_person_ids)
          .includes(course_offering: { production: :shows })
          .to_a

        course_registrations.each do |reg|
          offering = reg.course_offering
          offering.sessions.each do |session|
            next unless session.date_and_time >= cal_start && session.date_and_time <= cal_end
            @calendar_events << {
              date: session.date_and_time.to_date,
              time: session.date_and_time,
              title: offering.title,
              subtitle: "Course Session",
              path: my_course_path(offering),
              type: :course,
              color: "purple"
            }
          end
        end
      end

      # --- Audition sessions ---
      if @event_type_filter.include?("audition")
        selected_people = @people.select { |p| selected_person_ids.include?(p.id) }
        selected_groups = @groups.select { |g| selected_group_ids.include?(g.id) }
        auditionable_conditions = selected_people.map { |p| [ p.class.name, p.id ] }
        selected_groups.each { |g| auditionable_conditions << [ g.class.name, g.id ] }
      else
        auditionable_conditions = []
      end

      if auditionable_conditions.any?
        all_auditions = Audition
          .joins(:audition_session)
          .joins(audition_request: :audition_cycle)
          .where(audition_cycles: { finalize_audition_invitations: true })
          .where("audition_sessions.start_at >= ? AND audition_sessions.start_at <= ?", cal_start, cal_end)
          .where(
            auditionable_conditions.map { "(auditionable_type = ? AND auditionable_id = ?)" }.join(" OR "),
            *auditionable_conditions.flatten
          )
          .includes(audition_session: :production)
          .to_a

        all_auditions.each do |audition|
          session = audition.audition_session
          @calendar_events << {
            date: session.start_at.to_date,
            time: session.start_at,
            title: session.production.name,
            subtitle: "Audition",
            path: my_auditions_path,
            type: :audition,
            color: "amber"
          }
        end
      end

      # Group events by date for the calendar grid
      @events_by_date = @calendar_events.group_by { |e| e[:date] }

      # Group events by month for month navigation
      @events_by_month = @calendar_events.group_by { |e| e[:date].beginning_of_month }

      # Get events for current month
      month_start_date = @current_month.to_date
      month_end_date = month_start_date.end_of_month
      @month_events = @calendar_events
        .select { |e| e[:date] >= month_start_date && e[:date] <= month_end_date }
        .sort_by { |e| e[:time] }

      # === Alert sections (kept from original dashboard) ===

      # Unresolved vacancy invitations
      @pending_vacancy_invitations = RoleVacancyInvitation
        .unresolved
        .where(person_id: people_ids)
        .includes(role_vacancy: [ :role, { show: :production } ])
        .order("shows.date_and_time ASC")

      # Pending agreement signatures
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
