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
      @calendar_scope = params[:scope].presence || "my_assignments"

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

      if @calendar_scope == "all_shows"
        # Load ALL shows from productions the user is in (via talent pools)
        if show_event_types.any?
          production_ids = @productions.pluck(:id)
          all_shows = Show
            .where(production_id: production_ids)
            .where("date_and_time >= ? AND date_and_time <= ?", cal_start, cal_end)
            .where(canceled: false)
            .where.not(productions: { production_type: "course" })
            .where(event_type: show_event_types)
            .joins(:production)
            .includes(:production, :location, show_person_role_assignments: :role)
            .distinct.to_a

          # Pre-fetch IDs of shows user is signed up for
          signup_show_ids = if selected_person_ids.any?
            Show.joins(sign_up_form_instances: { sign_up_slots: :sign_up_registrations })
              .where(sign_up_registrations: { person_id: selected_person_ids, status: "confirmed" })
              .where(id: all_shows.map(&:id))
              .pluck(:id).to_set
          else
            Set.new
          end

          all_shows.each do |show|
            show_data_by_id[show.id] = show

            # Check if user has a direct role assignment on this show
            person_assignment = show.show_person_role_assignments
              .detect { |a| a.assignable_type == "Person" && selected_person_ids.include?(a.assignable_id) }
            group_assignment = person_assignment.nil? ? show.show_person_role_assignments
              .detect { |a| a.assignable_type == "Group" && selected_group_ids.include?(a.assignable_id) } : nil
            assignment = person_assignment || group_assignment
            has_signup = signup_show_ids.include?(show.id)

            if assignment || has_signup
              role_name = assignment&.role&.name
              color = case show.event_type
              when "rehearsal" then "blue"
              when "meeting" then "green"
              else "pink"
              end
              @calendar_events << {
                date: show.date_and_time.to_date,
                time: show.date_and_time,
                title: show.production.name,
                subtitle: role_name || (has_signup ? "Signed Up" : show.event_type.titleize),
                path: my_show_path(show),
                type: :show,
                color: color,
                event_type: show.event_type
              }
            else
              @calendar_events << {
                date: show.date_and_time.to_date,
                time: show.date_and_time,
                title: show.secondary_name.presence || show.production.name,
                subtitle: show.date_and_time.strftime("%-I:%M%p").downcase,
                path: my_show_path(show),
                type: :show,
                color: "gray",
                event_type: show.event_type
              }
            end
          end
        end
      else
      if show_event_types.any? && selected_person_ids.any?
        # Shows where the person has a direct role assignment
        person_assigned_shows = Show
          .joins(:show_person_role_assignments)
          .where(show_person_role_assignments: { assignable_type: "Person", assignable_id: selected_person_ids })
          .where("shows.date_and_time >= ? AND shows.date_and_time <= ?", cal_start, cal_end)
          .where(shows: { canceled: false })
          .where.not(productions: { production_type: "course" })
          .where(shows: { event_type: show_event_types })
          .joins(:production)
          .includes(:production, :location, show_person_role_assignments: :role)
          .distinct.to_a

        # Shows where the person has a confirmed sign-up registration
        person_signup_shows = Show
          .joins(sign_up_form_instances: { sign_up_slots: :sign_up_registrations })
          .where(sign_up_registrations: { person_id: selected_person_ids, status: "confirmed" })
          .where("shows.date_and_time >= ? AND shows.date_and_time <= ?", cal_start, cal_end)
          .where(shows: { canceled: false })
          .where.not(productions: { production_type: "course" })
          .where(shows: { event_type: show_event_types })
          .joins(:production)
          .includes(:production, :location, show_person_role_assignments: :role)
          .distinct.to_a

        signup_show_ids_my = person_signup_shows.map(&:id).to_set

        (person_assigned_shows + person_signup_shows).uniq(&:id).each do |show|
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
            subtitle: role_name || (signup_show_ids_my.include?(show.id) ? "Signed Up" : show.event_type.titleize),
            path: my_show_path(show),
            type: :show,
            color: color,
            event_type: show.event_type
          }
        end
      end

      # Group shows (direct role assignments only)
      if show_event_types.any? && selected_group_ids.any?
        group_assigned_shows = Show
          .joins(:show_person_role_assignments)
          .where(show_person_role_assignments: { assignable_type: "Group", assignable_id: selected_group_ids })
          .where("shows.date_and_time >= ? AND shows.date_and_time <= ?", cal_start, cal_end)
          .where(shows: { canceled: false })
          .where.not(productions: { production_type: "course" })
          .where(shows: { event_type: show_event_types })
          .joins(:production)
          .includes(:production, :location, show_person_role_assignments: :role)
          .distinct.to_a

        group_assigned_shows.each do |show|
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
      end # end of my_assignments scope

      # --- Course sessions ---
      if @event_type_filter.include?("course") && selected_person_ids.any?
        # Courses where user is a registered student
        course_registrations = CourseRegistration
          .confirmed
          .where(person_id: selected_person_ids)
          .includes(course_offering: { production: :shows })
          .to_a

        registered_offering_ids = course_registrations.map(&:course_offering_id).to_set

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

        # Courses where user is an instructor (not already included via registration)
        instructor_offerings = CourseOffering
          .joins(:course_offering_instructors)
          .where(course_offering_instructors: { person_id: selected_person_ids })
          .where.not(id: registered_offering_ids.to_a)
          .includes(production: :shows)
          .to_a

        instructor_offerings.each do |offering|
          offering.sessions.each do |session|
            next unless session.date_and_time >= cal_start && session.date_and_time <= cal_end
            @calendar_events << {
              date: session.date_and_time.to_date,
              time: session.date_and_time,
              title: offering.title,
              subtitle: "Instructor",
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
