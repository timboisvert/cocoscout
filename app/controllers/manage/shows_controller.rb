# frozen_string_literal: true

module Manage
  class ShowsController < Manage::ManageController
    before_action :set_production, except: [ :org_index, :org_calendar ]
    before_action :check_production_access, except: [ :org_index, :org_calendar ]
    before_action :set_show, only: %i[show edit update destroy cancel cancel_show delete_show uncancel link_show unlink_show transfer transfer_select transfer_preview toggle_signup_based_casting toggle_attendance attendance update_attendance create_walkin]
    before_action :ensure_user_is_manager, except: %i[index show recurring_series org_index org_calendar]

    # Org-level shows index (moved from org_shows_controller)
    def org_index
      # Store the shows filter
      @filter = params[:filter] || session[:shows_filter] || "upcoming"
      session[:shows_filter] = @filter

      # Handle event type filter (show, rehearsal, meeting, class, workshop) - checkboxes
      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all

      # Get productions the user has access to
      @productions = Current.user.accessible_productions.order(:name)

      # Get shows across all productions, eager load location, event_linkage, and production
      @shows = Show.where(production: @productions)
                   .includes(:location, :production, event_linkage: :shows)

      # Apply event type filter
      @shows = @shows.where(event_type: @event_type_filter)

      case @filter
      when "past"
        @shows = @shows.where("shows.date_and_time <= ?", Time.current).order(Arel.sql("shows.date_and_time DESC"))
      else
        @filter = "upcoming"
        @shows = @shows.where("shows.date_and_time > ?", Time.current).order(Arel.sql("shows.date_and_time ASC"))
      end

      # Load into memory
      @shows = @shows.to_a

      # Load cast and vacancy data for each show
      show_ids = @shows.map(&:id)

      # Get all assignments for these shows
      assignments = ShowPersonRoleAssignment
        .where(show_id: show_ids)
        .includes(:role, assignable: { profile_headshots: { image_attachment: :blob } })
        .to_a

      @assignments_by_show = assignments.group_by(&:show_id)

      # Get all roles for these shows
      @roles_by_show = {}
      @shows.each do |show|
        @roles_by_show[show.id] = show.available_roles.to_a
      end

      # Get open vacancies for these shows
      all_vacancies = RoleVacancy
        .where(status: %w[open finding_replacement not_filling])
        .joins("LEFT JOIN role_vacancy_shows ON role_vacancy_shows.role_vacancy_id = role_vacancies.id")
        .where("role_vacancies.show_id IN (?) OR role_vacancy_shows.show_id IN (?)", show_ids, show_ids)
        .distinct
        .includes(:role, :vacated_by, :affected_shows)
        .to_a

      # Build cant_make_it_by_assignment for each show
      @cant_make_it_by_show = {}
      all_vacancies.each do |vacancy|
        next unless vacancy.vacated_by.present?

        affected_show_ids = vacancy.affected_shows.any? ? vacancy.affected_shows.pluck(:id) : [ vacancy.show_id ]

        affected_show_ids.each do |affected_show_id|
          next unless show_ids.include?(affected_show_id)
          @cant_make_it_by_show[affected_show_id] ||= {}
          key = [ vacancy.vacated_by_type, vacancy.vacated_by_id ]
          @cant_make_it_by_show[affected_show_id][key] = vacancy
        end
      end

      # Load sign-up registrations for shows that have linked sign-up forms
      sign_up_registrations = SignUpRegistration
        .joins(sign_up_slot: :sign_up_form_instance)
        .where(sign_up_form_instances: { show_id: show_ids })
        .where(status: %w[confirmed waitlisted])
        .includes(:person, person: { profile_headshots: { image_attachment: :blob } }, sign_up_slot: { sign_up_form_instance: :sign_up_form })
        .to_a

      @sign_up_registrations_by_show = sign_up_registrations.group_by { |r| r.sign_up_slot.sign_up_form_instance.show_id }
    end

    # Org-level shows calendar (moved from org_shows_controller)
    def org_calendar
      # Store the shows filter
      @filter = params[:filter] || session[:shows_filter] || "upcoming"
      session[:shows_filter] = @filter

      # Get productions the user has access to
      @productions = Current.user.accessible_productions.order(:name)

      # Get shows across all productions, eager load location and production
      @shows = Show.where(production: @productions)
                   .includes(:location, :production)

      case @filter
      when "past"
        @shows = @shows.where("shows.date_and_time <= ?", Time.current).order(:date_and_time)
      else
        @filter = "upcoming"
        @shows = @shows.where("shows.date_and_time > ?", Time.current).order(:date_and_time)
      end

      # Load into memory and group shows by month for calendar display
      @shows_by_month = @shows.to_a.group_by { |show| show.date_and_time.beginning_of_month }
    end

    def index
      # Store the shows filter
      @filter = params[:filter] || session[:shows_filter] || "upcoming"
      session[:shows_filter] = @filter

      # Handle event type filter (show, rehearsal, meeting, class, workshop) - checkboxes
      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all

      # Get the shows using the shows filter, eager load location and event_linkage to avoid N+1
      @shows = @production.shows.includes(:location, event_linkage: :shows)

      # Apply event type filter
      @shows = @shows.where(event_type: @event_type_filter)

      case @filter
      when "past"
        @shows = @shows.where("shows.date_and_time <= ?", Time.current).order(Arel.sql("shows.date_and_time DESC"))
      else
        @filter = "upcoming"
        @shows = @shows.where("shows.date_and_time > ?", Time.current).order(Arel.sql("shows.date_and_time ASC"))
      end

      # Load into memory to avoid multiple queries
      @shows = @shows.to_a

      # Load cast and vacancy data for each show
      show_ids = @shows.map(&:id)

      # Get all assignments for these shows
      assignments = ShowPersonRoleAssignment
        .where(show_id: show_ids)
        .includes(:role, assignable: { profile_headshots: { image_attachment: :blob } })
        .to_a

      @assignments_by_show = assignments.group_by(&:show_id)

      # Get all roles for these shows
      @roles_by_show = {}
      @shows.each do |show|
        @roles_by_show[show.id] = show.available_roles.to_a
      end

      # Get open vacancies for these shows (includes open, finding_replacement, not_filling)
      all_vacancies = RoleVacancy
        .where(status: %w[open finding_replacement not_filling])
        .joins("LEFT JOIN role_vacancy_shows ON role_vacancy_shows.role_vacancy_id = role_vacancies.id")
        .where("role_vacancies.show_id IN (?) OR role_vacancy_shows.show_id IN (?)", show_ids, show_ids)
        .distinct
        .includes(:role, :vacated_by, :affected_shows)
        .to_a

      # Build cant_make_it_by_assignment for each show
      # Keyed by [assignable_type, assignable_id] to match assignment's assignable
      @cant_make_it_by_show = {}
      all_vacancies.each do |vacancy|
        next unless vacancy.vacated_by.present?

        # Determine which shows this vacancy affects
        affected_show_ids = vacancy.affected_shows.any? ? vacancy.affected_shows.pluck(:id) : [ vacancy.show_id ]

        affected_show_ids.each do |affected_show_id|
          next unless show_ids.include?(affected_show_id)
          @cant_make_it_by_show[affected_show_id] ||= {}
          key = [ vacancy.vacated_by_type, vacancy.vacated_by_id ]
          @cant_make_it_by_show[affected_show_id][key] = vacancy
        end
      end

      # Load sign-up registrations for shows that have linked sign-up forms
      sign_up_registrations = SignUpRegistration
        .joins(sign_up_slot: :sign_up_form_instance)
        .where(sign_up_form_instances: { show_id: show_ids })
        .where(status: %w[confirmed waitlisted])
        .includes(:person, person: { profile_headshots: { image_attachment: :blob } }, sign_up_slot: { sign_up_form_instance: :sign_up_form })
        .to_a

      @sign_up_registrations_by_show = sign_up_registrations.group_by { |r| r.sign_up_slot.sign_up_form_instance.show_id }

      # Load contract services for third-party productions
      if @production.type_third_party? && @production.contract.present?
        @contract_services = @production.contract.draft_services
      else
        @contract_services = []
      end
    end

    def show
      # Preload data for the cast_card partial to avoid N+1 queries
      # Use available_roles which respects show.use_custom_roles
      @roles = @show.available_roles.to_a
      @roles_count = @roles.sum { |r| r.quantity || 1 }

      # Preload assignables (people and groups) with their headshots
      assignments = @show.show_person_role_assignments.to_a

      person_ids = assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
      group_ids = assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq

      @people_by_id = Person
                      .where(id: person_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .index_by(&:id)

      @groups_by_id = Group
                      .where(id: group_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .index_by(&:id)

      # Load open vacancies for this show
      # Include vacancies where this show is the primary show OR in the affected_shows
      @open_vacancies = RoleVacancy
                          .open
                          .joins("LEFT JOIN role_vacancy_shows ON role_vacancy_shows.role_vacancy_id = role_vacancies.id")
                          .where("role_vacancies.show_id = ? OR role_vacancy_shows.show_id = ?", @show.id, @show.id)
                          .distinct
                          .includes(:role, :affected_shows, :vacated_by)
                          .to_a

      # Build open vacancies by role for non-linked shows (person removed, role empty)
      @open_vacancies_by_role = @open_vacancies.group_by(&:role_id)

      # Load all vacancies for this show (including not_filling, filled, cancelled) for the vacancies section
      @all_vacancies = RoleVacancy
                          .joins("LEFT JOIN role_vacancy_shows ON role_vacancy_shows.role_vacancy_id = role_vacancies.id")
                          .where("role_vacancies.show_id = ? OR role_vacancy_shows.show_id = ?", @show.id, @show.id)
                          .distinct
                          .includes(:role, :affected_shows, :vacated_by, :filled_by)
                          .order(created_at: :desc)
                          .to_a

      # Load cancelled/open vacancies for linked shows (person still cast but can't make it)
      @cancelled_vacancies_by_assignment = @show.cancelled_vacancies_by_assignment

      # Load sign-up registrations if this show has a linked sign-up form
      @sign_up_registrations = @show.sign_up_registrations.includes(person: { profile_headshots: { image_attachment: :blob } }).to_a
    end

    def calendar
      # Store the shows filter
      @filter = params[:filter] || session[:shows_filter] || "upcoming"

      session[:shows_filter] = @filter

      # Get the shows using the shows filter, eager load location to avoid N+1
      @shows = @production.shows.includes(:location)

      case @filter
      when "past"
        @shows = @shows.where("shows.date_and_time <= ?", Time.current).order(:date_and_time)
      else
        @filter = "upcoming"
        @shows = @shows.where("shows.date_and_time > ?", Time.current).order(:date_and_time)
      end

      # Load into memory and group shows by month for calendar display
      @shows_by_month = @shows.to_a.group_by { |show| show.date_and_time.beginning_of_month }
    end

    # GET /manage/productions/:production_id/shows/recurring_series
    # Modal to view and manage a recurring series
    def recurring_series
      @recurrence_group_id = params[:recurrence_group_id]
      return head :not_found unless @recurrence_group_id.present?

      @shows_in_series = @production.shows.in_recurrence_group(@recurrence_group_id).order(:date_and_time).to_a
      return head :not_found if @shows_in_series.empty?

      @first_show = @shows_in_series.first
      @last_show = @shows_in_series.last
      @pattern = @first_show.recurrence_pattern

      # Infer pattern from dates if not stored
      if @pattern.blank? && @shows_in_series.length >= 2
        @pattern = infer_recurrence_pattern(@shows_in_series)
      end

      @upcoming_shows = @shows_in_series.select { |s| s.date_and_time > Time.current }
      @past_shows = @shows_in_series.select { |s| s.date_and_time <= Time.current }

      respond_to do |format|
        format.html { render partial: "manage/shows/recurring_series_modal", layout: false }
        format.turbo_stream
      end
    end

    # POST /manage/productions/:production_id/shows/extend_series
    # Extend a recurring series with more shows
    def extend_series
      @recurrence_group_id = params[:recurrence_group_id]
      return head :not_found unless @recurrence_group_id.present?

      @shows_in_series = @production.shows.in_recurrence_group(@recurrence_group_id).order(:date_and_time).to_a
      return head :not_found if @shows_in_series.empty?

      @last_show = @shows_in_series.last
      @pattern = @last_show.recurrence_pattern || infer_recurrence_pattern(@shows_in_series)

      # Calculate new end date
      extend_through = case params[:extend_duration]
      when "3_months"
        @last_show.date_and_time.to_date + 3.months
      when "6_months"
        @last_show.date_and_time.to_date + 6.months
      when "12_months"
        @last_show.date_and_time.to_date + 12.months
      when "end_of_year"
        end_of_year = Date.new(@last_show.date_and_time.year, 12, 31)
        # If we're already past end of year or at end of year, extend to next year
        end_of_year <= @last_show.date_and_time.to_date ? Date.new(@last_show.date_and_time.year + 1, 12, 31) : end_of_year
      when "custom"
        Date.parse(params[:custom_end_date])
      else
        @last_show.date_and_time.to_date + 3.months
      end

      # Generate new dates starting from the last show
      new_dates = generate_recurring_dates(@last_show.date_and_time, @pattern, extend_through)
      # Remove the first date as it's the last existing show
      new_dates = new_dates.drop(1)

      if new_dates.empty?
        redirect_to manage_production_shows_path(@production), alert: "No new dates to add. The series may already extend past the selected date."
        return
      end

      created_count = 0
      new_dates.each do |datetime|
        show = @production.shows.new(
          event_type: @last_show.event_type,
          secondary_name: @last_show.secondary_name,
          location_id: @last_show.location_id,
          is_online: @last_show.is_online,
          online_location_info: @last_show.online_location_info,
          casting_enabled: @last_show.casting_enabled,
          casting_source: @last_show.casting_source,
          public_profile_visible: @last_show.public_profile_visible,
          date_and_time: datetime,
          recurrence_group_id: @recurrence_group_id,
          recurrence_pattern: @pattern
        )
        created_count += 1 if show.save
      end

      redirect_to manage_production_shows_path(@production),
                  notice: "Extended series with #{created_count} new events through #{extend_through.strftime('%B %d, %Y')}"
    end

    def new
      @show = @production.shows.new

      # Set default casting_enabled based on event_type from config
      @show.casting_enabled = EventTypes.casting_enabled_default(@show.event_type || "show")

      # Set default call_time_enabled based on event_type from config
      @show.call_time_enabled = EventTypes.call_time_enabled_default(@show.event_type || "show")

      # Set default location if available
      default_location = Current.organization.locations.find_by(default: true)
      @show.location = default_location if default_location

      # Handle duplication
      return unless params[:duplicate].present?

      @original_show = @production.shows.find_by(id: params[:duplicate])
      return unless @original_show.present?

      @show.date_and_time = @original_show.date_and_time
      @show.event_type = @original_show.event_type
      @show.secondary_name = @original_show.secondary_name
      @show.location = @original_show.location
      @show.casting_enabled = @original_show.casting_enabled
      @show.use_custom_roles = @original_show.use_custom_roles
      @show.call_time_enabled = @original_show.call_time_enabled
      @show.call_time = @original_show.call_time
    end

    def edit; end

    def create
      if params[:show][:event_frequency] == "recurring"
        create_recurring_events
      else
        # Check if this is a duplicate with the same date
        if params[:duplicate_from_id].present? && params[:confirm_same_date] != "true"
          original_show = @production.shows.find_by(id: params[:duplicate_from_id])
          if original_show.present?
            # Parse the submitted date_and_time
            submitted_date = begin
              DateTime.parse(params[:show][:date_and_time])
            rescue StandardError
              nil
            end
            if submitted_date.present? && submitted_date.to_date == original_show.date_and_time.to_date
              # Same date - need confirmation
              @show = Show.new(show_params.except(:event_frequency, :recurrence_pattern, :recurrence_end_type,
                                                  :recurrence_start_datetime, :recurrence_custom_end_date, :recurrence_edit_scope))
              @show.production = @production
              @original_show = original_show
              @needs_confirmation = true
              render :new, status: :unprocessable_entity
              return
            end
          end
        end

        # Filter out virtual attributes used only for recurring event logic
        filtered_params = show_params.except(:event_frequency, :recurrence_pattern, :recurrence_end_type,
                                             :recurrence_start_datetime, :recurrence_custom_end_date, :recurrence_edit_scope)
        @show = Show.new(filtered_params)
        @show.production = @production

        if @show.save
          # If duplicating from a show with custom roles, copy the roles
          if params[:duplicate_from_id].present?
            original_show = @production.shows.find_by(id: params[:duplicate_from_id])
            if original_show&.use_custom_roles? && original_show.custom_roles.any?
              copy_custom_roles_from(original_show, @show)
            end
          end

          redirect_to manage_production_shows_path(@production), notice: "Show was successfully created"
        else
          render :new, status: :unprocessable_entity
        end
      end
    end

    def create_recurring_events
      # Parse the datetime in the application's timezone
      start_datetime = Time.zone.parse(params[:show][:recurrence_start_datetime])
      pattern = params[:show][:recurrence_pattern]
      end_type = params[:show][:recurrence_end_type]

      # Calculate end date based on duration
      end_date = case end_type
      when "3_months"
                   start_datetime.to_date + 3.months
      when "6_months"
                   start_datetime.to_date + 6.months
      when "12_months"
                   start_datetime.to_date + 12.months
      when "end_of_year"
                   Date.new(start_datetime.year, 12, 31)
      when "custom"
                   Date.parse(params[:show][:recurrence_custom_end_date])
      else
                   start_datetime.to_date + 6.months # default
      end

      datetimes = []
      current_datetime = start_datetime

      # Store initial values for monthly_week pattern
      initial_day_of_week = start_datetime.wday
      initial_week_of_month = (start_datetime.day - 1) / 7 + 1

      # Generate datetimes based on pattern
      while current_datetime.to_date <= end_date
        case pattern
        when "daily"
          datetimes << current_datetime
          current_datetime += 1.day
        when "weekly"
          datetimes << current_datetime
          current_datetime += 1.week
        when "biweekly"
          datetimes << current_datetime
          current_datetime += 2.weeks
        when "monthly_date"
          datetimes << current_datetime
          current_datetime += 1.month
        when "monthly_week"
          datetimes << current_datetime
          # Move to next month, then find the same week and day
          next_month = current_datetime + 1.month
          # Find the first occurrence of the target day in the next month
          first_of_month = next_month.beginning_of_month
          days_until_target_day = (initial_day_of_week - first_of_month.wday) % 7
          first_occurrence = first_of_month + days_until_target_day.days
          # Add weeks to get to the target week, then preserve the original time
          target_date = first_occurrence + (initial_week_of_month - 1).weeks
          current_datetime = target_date.change(hour: start_datetime.hour, min: start_datetime.min,
                                                sec: start_datetime.sec)
        when "weekdays"
          datetimes << current_datetime if current_datetime.wday.between?(1, 5) # Monday to Friday
          current_datetime += 1.day
        end
      end

      # Generate a UUID for this recurrence group
      recurrence_group_id = SecureRandom.uuid

      # Determine casting_source - respect the clear_casting_source flag
      effective_casting_source = if params[:clear_casting_source] == "1"
        nil # Inherit from production
      else
        params[:show][:casting_source]
      end

      # Create shows for each datetime
      created_count = 0
      datetimes.each do |datetime|
        show = Show.new(
          event_type: params[:show][:event_type],
          secondary_name: params[:show][:secondary_name],
          location_id: params[:show][:location_id],
          is_online: params[:show][:is_online],
          online_location_info: params[:show][:online_location_info],
          casting_enabled: params[:show][:casting_enabled],
          casting_source: effective_casting_source,
          date_and_time: datetime,
          production: @production,
          recurrence_group_id: recurrence_group_id
        )
        created_count += 1 if show.save
      end

      redirect_to manage_production_shows_path(@production),
                  notice: "Successfully created #{created_count} recurring events"
    end

    def update
      # Check if this is a recurring event and what scope to edit
      if @show.recurring? && params[:show][:recurrence_edit_scope] == "all"
        # Check if recurrence pattern is being changed
        if params[:show][:recurrence_pattern].present?
          # Recreate the entire series with new pattern
          update_recurring_series
        else
          # Just update properties on all events in the group
          update_params = show_params.except(:recurrence_edit_scope, :date_and_time,
                                             :recurrence_pattern, :recurrence_start_datetime,
                                             :recurrence_end_type, :recurrence_custom_end_date)

          # Handle poster removal for all events in the group
          if update_params[:remove_poster] == "1"
            @show.recurrence_group.each do |show|
              show.poster.purge if show.poster.attached?
            end
          end
          update_params.delete(:remove_poster)

          updated_count = 0

          @show.recurrence_group.each do |show|
            updated_count += 1 if show.update(update_params)
          end

          redirect_to manage_show_path(@production, @show),
                      notice: "Successfully updated #{updated_count} events in the series",
                      status: :see_other
        end
      else
        # Update only this occurrence (remove from recurrence group if editing date/time)
        update_params = show_params.except(:recurrence_edit_scope, :recurrence_pattern,
                                           :recurrence_start_datetime, :recurrence_end_type,
                                           :recurrence_custom_end_date)

        # If date/time is being changed on a recurring event, unlink it from the group
        if @show.recurring? && update_params[:date_and_time].present? &&
           update_params[:date_and_time] != @show.date_and_time.to_s
          update_params[:recurrence_group_id] = nil
        end

        # Handle poster removal
        @show.poster.purge if update_params[:remove_poster] == "1" && @show.poster.attached?
        update_params.delete(:remove_poster)

        if @show.update(update_params)
          redirect_to manage_show_path(@production, @show),
                      notice: "#{@show.event_type.titleize} was successfully updated",
                      status: :see_other
        else
          render :edit, status: :unprocessable_entity
        end
      end
    end

    def update_recurring_series
      # Get the recurrence group ID before deleting
      recurrence_group_id = @show.recurrence_group_id

      # Store the properties we want to keep
      event_type = params[:show][:event_type] || @show.event_type
      secondary_name = params[:show][:secondary_name] || @show.secondary_name
      location_id = params[:show][:location_id] || @show.location_id
      is_online = params[:show][:is_online].nil? ? @show.is_online : params[:show][:is_online]
      online_location_info = params[:show][:online_location_info] || @show.online_location_info
      casting_enabled = params[:show][:casting_enabled].nil? ? @show.casting_enabled : params[:show][:casting_enabled]
      # Respect clear_casting_source flag
      casting_source = if params[:clear_casting_source] == "1"
        nil # Inherit from production
      else
        params[:show][:casting_source] || @show.casting_source
      end
      # Preserve call time settings
      call_time = params[:show][:call_time].presence || @show.call_time
      call_time_enabled = params[:show][:call_time_enabled].nil? ? @show.call_time_enabled : params[:show][:call_time_enabled]
      public_profile_visible = params[:show][:public_profile_visible].nil? ? @show.public_profile_visible : params[:show][:public_profile_visible]
      use_custom_roles = params[:show][:use_custom_roles].nil? ? @show.use_custom_roles : params[:show][:use_custom_roles]

      # Delete all existing events in the series
      @show.recurrence_group.destroy_all

      # Parse new recurrence parameters - use Time.zone.parse to respect application timezone
      start_datetime = Time.zone.parse(params[:show][:recurrence_start_datetime])
      pattern = params[:show][:recurrence_pattern]
      end_type = params[:show][:recurrence_end_type]

      # Calculate end date based on duration
      end_date = case end_type
      when "3_months"
                   start_datetime.to_date + 3.months
      when "6_months"
                   start_datetime.to_date + 6.months
      when "12_months"
                   start_datetime.to_date + 12.months
      when "end_of_year"
                   Date.new(start_datetime.year, 12, 31)
      when "custom"
                   Date.parse(params[:show][:recurrence_custom_end_date])
      else
                   start_datetime.to_date + 6.months # default
      end

      datetimes = []
      current_datetime = start_datetime

      # Store initial values for monthly_week pattern
      initial_day_of_week = start_datetime.wday
      initial_week_of_month = (start_datetime.day - 1) / 7 + 1

      # Generate datetimes based on pattern
      while current_datetime.to_date <= end_date
        case pattern
        when "weekly"
          datetimes << current_datetime
          current_datetime += 1.week
        when "biweekly"
          datetimes << current_datetime
          current_datetime += 2.weeks
        when "monthly_date"
          datetimes << current_datetime
          current_datetime += 1.month
        when "monthly_week"
          datetimes << current_datetime
          # Move to next month, then find the same week and day
          next_month = current_datetime + 1.month
          # Find the first occurrence of the target day in the next month
          first_of_month = next_month.beginning_of_month
          days_until_target_day = (initial_day_of_week - first_of_month.wday) % 7
          first_occurrence = first_of_month + days_until_target_day.days
          # Add weeks to get to the target week, then preserve the original time
          target_date = first_occurrence + (initial_week_of_month - 1).weeks
          current_datetime = target_date.change(hour: start_datetime.hour, min: start_datetime.min,
                                                sec: start_datetime.sec)
        end
      end

      # Create new shows for each datetime with the same recurrence group ID
      created_count = 0
      datetimes.each do |datetime|
        show = Show.new(
          event_type: event_type,
          secondary_name: secondary_name,
          location_id: location_id,
          is_online: is_online,
          online_location_info: online_location_info,
          casting_enabled: casting_enabled,
          casting_source: casting_source,
          call_time: call_time,
          call_time_enabled: call_time_enabled,
          public_profile_visible: public_profile_visible,
          use_custom_roles: use_custom_roles,
          date_and_time: datetime,
          production: @production,
          recurrence_group_id: recurrence_group_id
        )
        created_count += 1 if show.save
      end

      redirect_to manage_production_shows_path(@production),
                  notice: "Successfully recreated series with #{created_count} events"
    end

    def cancel
      # Shows the cancel/delete options page

      # Build cast member list for notification option
      if @show.recurring?
        all_show_ids = @show.recurrence_group.pluck(:id)
        cast_assignments = ShowPersonRoleAssignment
                            .where(show_id: all_show_ids)
                            .includes(:role)
        person_ids = cast_assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
        group_ids = cast_assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq
      else
        cast_assignments = @show.show_person_role_assignments.includes(:role)
        person_ids = cast_assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
        group_ids = cast_assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq
      end

      @cast_people = Person.where(id: person_ids).includes(profile_headshots: { image_attachment: :blob }).to_a
      @cast_groups = Group.where(id: group_ids).includes(:members, profile_headshots: { image_attachment: :blob }).to_a

      # Get unique role categories from assignments
      @role_categories = cast_assignments.map { |a| a.role&.category }.compact.uniq.sort

      # Get all unique people (including group members) with emails
      all_person_ids = Set.new(person_ids)
      @cast_groups.each do |group|
        group.group_memberships.each { |gm| all_person_ids << gm.person_id }
      end
      @people_with_email = Person.where(id: all_person_ids.to_a).includes(:user).select { |p| p.user.present? }
      @people_with_sms = @people_with_email.select { |p| p.user&.sms_notification_enabled?(:show_cancellation) }
    end

    def cancel_show
      scope = params[:scope] || "this"
      event_label = @show.event_type.titleize
      notify_cast = params[:notify_cast] == "1"
      role_categories = params[:role_categories]&.reject(&:blank?)

      if scope == "all" && @show.recurring?
        # Cancel all occurrences in the recurrence group
        shows_to_cancel = @show.recurrence_group.where(canceled: false).to_a
        count = @show.recurrence_group.update_all(canceled: true)

        # Send notifications if requested (uses template automatically)
        if notify_cast
          send_cancellation_notifications(shows_to_cancel, nil, nil, role_categories)
        end

        redirect_to manage_production_shows_path(@production),
                    notice: "Successfully canceled #{count} #{event_label.pluralize.downcase}",
                    status: :see_other
      else
        # Cancel just this occurrence
        @show.update!(canceled: true)

        # Send notifications if requested (uses template automatically)
        if notify_cast
          send_cancellation_notifications([ @show ], nil, nil, role_categories)
        end

        redirect_to manage_production_shows_path(@production),
                    notice: "#{event_label} was successfully canceled",
                    status: :see_other
      end
    end

    def delete_show
      scope = params[:scope] || "this"
      event_label = @show.event_type.titleize

      if scope == "all" && @show.recurring?
        # Delete all occurrences in the recurrence group
        count = @show.recurrence_group.count
        @show.recurrence_group.destroy_all
        redirect_to manage_production_shows_path(@production),
                    notice: "Successfully deleted #{count} #{event_label.pluralize.downcase}",
                    status: :see_other
      else
        # Delete just this occurrence
        @show.destroy!
        redirect_to manage_production_shows_path(@production),
                    notice: "#{event_label} was successfully deleted",
                    status: :see_other
      end
    end

    def uncancel
      scope = params[:scope] || "this"
      event_label = @show.event_type.titleize

      if scope == "all" && @show.recurring?
        # Uncancel all canceled occurrences in the recurrence group
        count = @show.recurrence_group.where(canceled: true).update_all(canceled: false)
        redirect_to manage_production_shows_path(@production),
                    notice: "Successfully uncanceled #{count} #{event_label.pluralize.downcase}",
                    status: :see_other
      else
        # Uncancel just this occurrence
        @show.update!(canceled: false)
        redirect_to manage_production_shows_path(@production),
                    notice: "#{event_label} was successfully uncanceled",
                    status: :see_other
      end
    end

    # Link another show to this show's event linkage
    def link_show
      target_show = @production.shows.find(params[:target_show_id])
      linkage_role = params[:linkage_role] || "sibling"

      # Validate role
      unless %w[sibling child].include?(linkage_role)
        return render json: { error: "Invalid linkage role" }, status: :unprocessable_entity
      end

      # Create or get the event linkage
      if @show.event_linkage.present?
        event_linkage = @show.event_linkage
      else
        # Create new linkage with this show as the primary (the one the user started from)
        event_linkage = EventLinkage.create!(production: @production, primary_show: @show)
        @show.update!(event_linkage: event_linkage, linkage_role: :sibling)
      end

      # Check if target show is already linked elsewhere
      if target_show.event_linkage.present? && target_show.event_linkage != event_linkage
        return render json: { error: "That event is already part of another linkage" }, status: :unprocessable_entity
      end

      # Link the target show
      target_show.update!(event_linkage: event_linkage, linkage_role: linkage_role)

      # If target show has a poster and this show doesn't, copy it
      if target_show.poster.attached? && !@show.poster.attached?
        @show.poster.attach(target_show.poster.blob)
      # Or if this show has a poster and target doesn't, copy to target
      elsif @show.poster.attached? && !target_show.poster.attached?
        target_show.poster.attach(@show.poster.blob)
      end

      respond_to do |format|
        format.turbo_stream {
          @show.reload
          render turbo_stream: [
            turbo_stream.replace(
              "linked-events-modal-body",
              partial: "manage/shows/linked_events_modal_body",
              locals: { show: @show, production: @production }
            ),
            turbo_stream.replace(
              "linked-events-list",
              partial: "manage/shows/linked_events_list",
              locals: { show: @show, production: @production }
            )
          ]
        }
        format.json {
          render json: {
            success: true,
            message: "Event linked successfully",
            redirect_url: manage_edit_show_path(@production, @show, anchor: "tab-5")
          }
        }
      end
    end

    # Remove this show from its event linkage
    def unlink_show
      event_linkage = @show.event_linkage

      unless event_linkage
        return render json: { error: "This event is not linked" }, status: :unprocessable_entity
      end

      # Get the requesting show (the one whose view needs to be refreshed)
      requesting_show_id = params[:requesting_show_id]
      requesting_show = requesting_show_id ? @production.shows.find_by(id: requesting_show_id) : nil

      # Remove this show from the linkage
      @show.update!(event_linkage: nil, linkage_role: nil)

      # If only one show remains in the linkage, unlink it too and delete the linkage
      remaining_shows = event_linkage.shows.reload
      if remaining_shows.count == 1
        remaining_shows.first.update!(event_linkage: nil, linkage_role: nil)
        event_linkage.destroy
      elsif remaining_shows.count == 0
        event_linkage.destroy
      end

      respond_to do |format|
        format.turbo_stream {
          # Refresh the requesting show's view, not this show's view
          show_to_render = requesting_show || @show
          show_to_render.reload
          render turbo_stream: [
            turbo_stream.replace(
              "linked-events-modal-body",
              partial: "manage/shows/linked_events_modal_body",
              locals: { show: show_to_render, production: @production }
            ),
            turbo_stream.replace(
              "linked-events-list",
              partial: "manage/shows/linked_events_list",
              locals: { show: show_to_render, production: @production }
            )
          ]
        }
        format.json {
          render json: {
            success: true,
            message: "Event unlinked successfully",
            redirect_url: manage_edit_show_path(@production, @show, anchor: "tab-5")
          }
        }
      end
    end

    # Delete the entire event linkage (unlinks all shows)
    def delete_linkage
      event_linkage = @show.event_linkage

      unless event_linkage
        return render json: { error: "This event is not linked" }, status: :unprocessable_entity
      end

      # Unlink all shows from this linkage
      event_linkage.shows.update_all(event_linkage_id: nil, linkage_role: nil)

      # Delete the linkage
      event_linkage.destroy

      render json: {
        success: true,
        message: "All events unlinked successfully",
        redirect_url: manage_edit_show_path(@production, @show, anchor: "tab-5")
      }
    end

    def destroy
      # Legacy destroy action - redirects to new cancel page
      redirect_to manage_cancel_show_form_path(@production, @show)
    end

    def transfer_select
      # Get all productions the user has access to, except the current one
      # Exclude third-party productions (they can't own shows)
      @available_productions = Current.user.accessible_productions
                                       .where.not(id: @production.id)
                                       .where(organization: Current.organization)
                                       .where.not(production_type: :third_party)
                                       .order(:name)

      if @available_productions.empty?
        redirect_to manage_show_path(@production, @show),
                    alert: "No other productions available to transfer to"
      end
    end

    def transfer_preview
      @target_production = Current.user.accessible_productions.find_by(id: params[:target_production_id])

      unless @target_production
        redirect_to manage_transfer_show_select_path(@production, @show),
                    alert: "Please select a valid target production"
        return
      end

      @recurring_scope = params[:recurring_scope] || "single"
      @linked_scope = params[:linked_scope] || "single"

      # Determine which shows to transfer
      @shows_to_transfer = determine_shows_to_transfer(@show, @recurring_scope, @linked_scope)

      # Build a summary of what's being transferred
      @transfer_summary = build_transfer_summary(@shows_to_transfer, @target_production)
    end

    def transfer
      target_production_id = params[:target_production_id]
      @target_production = Current.user.accessible_productions.find_by(id: target_production_id)

      unless @target_production
        redirect_to manage_show_path(@production, @show),
                    alert: "Target production not found or you don't have access"
        return
      end

      if @target_production.id == @production.id
        redirect_to manage_show_path(@production, @show),
                    alert: "Cannot move to the same production"
        return
      end

      recurring_scope = params[:recurring_scope] || "single"
      linked_scope = params[:linked_scope] || "single"

      # Determine which shows to transfer
      shows_to_transfer = determine_shows_to_transfer(@show, recurring_scope, linked_scope)

      # Perform the transfers
      success_count = 0
      errors = []

      shows_to_transfer.each do |show|
        result = ShowTransferService.transfer(show, @target_production)
        if result[:success]
          success_count += 1
        else
          errors << "#{show.event_type} on #{show.date_and_time.strftime('%B %-d')}: #{result[:error]}"
        end
      end

      if errors.empty?
        # Switch to the target production in the session
        session[:current_production_id_for_organization] ||= {}
        session[:current_production_id_for_organization]["#{Current.user.id}_#{Current.organization.id}"] = @target_production.id

        event_word = success_count == 1 ? "event" : "events"
        redirect_to manage_show_path(@target_production, @show),
                    notice: "Successfully transferred #{success_count} #{event_word} to #{@target_production.name}"
      else
        redirect_to manage_show_path(@production, @show),
                    alert: "Some transfers failed: #{errors.join(', ')}"
      end
    end

    def toggle_signup_based_casting
      enabled = params[:enabled] == "true" || params[:enabled] == true

      if enabled
        result = @show.enable_signup_based_casting!
        if result[:success]
          flash[:notice] = "Sign-up based casting enabled. #{result[:synced_count]} attendee(s) synced from sign-ups."
        else
          flash[:alert] = result[:error] || "Failed to enable sign-up based casting"
        end
      else
        result = @show.disable_signup_based_casting!
        if result[:success]
          flash[:notice] = "Sign-up based casting disabled."
        else
          flash[:alert] = result[:error] || "Failed to disable sign-up based casting"
        end
      end

      respond_to do |format|
        format.html { redirect_to manage_edit_show_path(@production, @show) }
        format.turbo_stream { redirect_to manage_edit_show_path(@production, @show) }
        format.json { render json: { success: result[:success], enabled: enabled } }
      end
    end

    def toggle_attendance
      enabled = params[:enabled] == "true" || params[:enabled] == true
      @show.update!(attendance_enabled: enabled)

      respond_to do |format|
        format.html { redirect_to manage_edit_show_path(@production, @show) }
        format.turbo_stream { redirect_to manage_edit_show_path(@production, @show) }
        format.json { render json: { success: true, enabled: enabled } }
      end
    end

    def attendance
      @attendance_records = @show.attendance_records_for_all_cast
      @attendance_summary = @show.attendance_summary

      respond_to do |format|
        format.html { render :attendance }
        format.json do
          records_json = @attendance_records.map do |rec|
            person = rec[:person]
            headshot_variant = person&.safe_headshot_variant(:thumb)
            headshot_url = headshot_variant ? url_for(headshot_variant) : nil

            {
              assignment: {
                id: rec[:assignment].id,
                role: { name: rec[:assignment].role&.name }
              },
              record: rec[:record].persisted? ? { status: rec[:record].status } : nil,
              person: {
                id: person&.id,
                name: person&.name,
                initials: person&.initials,
                headshot_url: headshot_url
              }
            }
          end
          render json: { records: records_json, summary: @attendance_summary }
        end
      end
    end

    def update_attendance
      # Permit each record ID with its status value (present, absent, late, excused, unknown)
      raw_attendance = params.require(:attendance)
      valid_statuses = %w[present absent excused unknown]
      attendance_params = {}
      raw_attendance.each do |key, value|
        attendance_params[key.to_s] = value.to_s if valid_statuses.include?(value.to_s)
      end

      attendance_params.each do |record_id, status|
        if record_id.start_with?("signup_")
          # Handle sign-up registration attendance
          signup_id = record_id.sub("signup_", "")
          record = ShowAttendanceRecord.find_or_initialize_by(
            show: @show,
            sign_up_registration_id: signup_id
          )
        else
          # Handle cast member attendance
          record = ShowAttendanceRecord.find_or_initialize_by(
            show: @show,
            show_person_role_assignment_id: record_id
          )
        end
        record.update!(status: status)
      end

      respond_to do |format|
        format.html { redirect_to manage_edit_show_path(@production, @show), notice: "Attendance updated successfully." }
        format.turbo_stream { redirect_to manage_edit_show_path(@production, @show), notice: "Attendance updated successfully." }
        format.json { render json: { success: true } }
      end
    end

    def create_walkin
      email = params.require(:email)
      name = params[:name]

      # Search for existing person by email
      person = Person.find_by(email: email)

      if person
        # Check if this person already has an attendance record for this show
        # Could be via direct walk-in (person_id) or via role assignment
        existing_walkin = @show.show_attendance_records.find_by(person_id: person.id)
        if existing_walkin
          respond_to do |format|
            format.json do
              render json: {
                success: false,
                error: "#{person.name} is already marked as attending this event"
              }, status: :unprocessable_entity
            end
          end
          return
        end

        # Check if they're assigned to this show (via role assignment)
        existing_assignment = @show.show_person_role_assignments.find_by(assignable: person)
        if existing_assignment
          respond_to do |format|
            format.json do
              render json: {
                success: false,
                error: "#{person.name} is already cast in this event. Use the attendance list to mark them present."
              }, status: :unprocessable_entity
            end
          end
          return
        end

        # Person exists - ensure they're in current organization
        unless person.organizations.include?(Current.organization)
          person.organizations << Current.organization
        end
      else
        # Person doesn't exist - create new person
        person = Person.new(
          name: name.presence || email.split("@")[0],
          email: email
        )

        unless person.save
          respond_to do |format|
            format.json do
              render json: {
                success: false,
                error: person.errors.full_messages.join(", ")
              }, status: :unprocessable_entity
            end
          end
          return
        end

        # Add to organization
        person.organizations << Current.organization
      end

      # Send invitation if person doesn't have a user account yet
      unless person.user
        user = User.create!(
          email_address: person.email,
          password: User.generate_secure_password
        )
        person.update!(user: user)

        person_invitation = PersonInvitation.create!(
          email: person.email,
          organization: Current.organization
        )
        Manage::PersonMailer.person_invitation(person_invitation, nil, nil).deliver_later
      end

      # Create attendance record marked as present (walk-in linked to person)
      record = ShowAttendanceRecord.new(
        show: @show,
        person: person,
        status: "present"
      )

      if record.save
        respond_to do |format|
          format.json do
            render json: {
              success: true,
              person: {
                id: person.id,
                name: person.name,
                email: person.email
              }
            }
          end
        end
      else
        respond_to do |format|
          format.json do
            render json: {
              success: false,
              error: record.errors.full_messages.join(", ")
            }, status: :unprocessable_entity
          end
        end
      end
    rescue ActionController::ParameterMissing
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            error: "Email is required"
          }, status: :unprocessable_entity
        end
      end
    rescue StandardError => e
      Rails.logger.error("Walk-in creation error: #{e.message}")
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            error: "An unexpected error occurred. Please try again."
          }, status: :internal_server_error
        end
      end
    end

    private

    def set_production
      if Current.organization
        @production = Current.organization.productions.find(params[:production_id])
        sync_current_production(@production)
      else
        redirect_to select_organization_path, alert: "Please select an organization first."
      end
    end

    def set_show
      show_id = params[:show_id] || params[:id]
      @show = Show
              .includes(
                :location,
                :custom_roles,
                show_person_role_assignments: :role,
                poster_attachment: :blob,
                production: { posters: { image_attachment: :blob } }
              )
              .find(show_id)
    end

    # Determine which shows to transfer based on recurring/linked scope
    def determine_shows_to_transfer(show, recurring_scope, linked_scope)
      shows = [ show ]

      # If part of recurring series and user wants all recurring
      if recurring_scope == "all" && show.recurring?
        recurring_shows = show.recurrence_siblings.to_a
        shows.concat(recurring_shows)
      end

      # If linked and user wants all linked
      if linked_scope == "all" && show.linked?
        linked_shows = show.event_linkage.shows.where.not(id: shows.map(&:id)).to_a
        shows.concat(linked_shows)
      end

      shows.uniq
    end

    # Build a summary of what data will be transferred
    def build_transfer_summary(shows, target_production)
      show_ids = shows.map(&:id)

      summary = {
        cast_count: ShowPersonRoleAssignment.where(show_id: show_ids).count,
        custom_roles_count: Role.where(show_id: show_ids).count,
        signup_forms_count: SignUpFormInstance.where(show_id: show_ids).count,
        financials_count: ShowFinancials.where(show_id: show_ids).count,
        vacancies_count: RoleVacancy.where(show_id: show_ids).count,
        warnings: []
      }

      # Check if there are any performers not in the target production's talent pool
      cast_person_ids = ShowPersonRoleAssignment
        .where(show_id: show_ids, assignable_type: "Person")
        .pluck(:assignable_id)
        .uniq

      target_talent_pool = target_production.effective_talent_pool
      target_production_person_ids = target_talent_pool.talent_pool_memberships
        .where(member_type: "Person")
        .pluck(:member_id)

      people_not_in_target = cast_person_ids - target_production_person_ids
      if people_not_in_target.any?
        summary[:warnings] << "#{people_not_in_target.count} cast member(s) are not in #{target_production.name}'s talent pool"
      end

      # Check if linked events are being split
      shows.each do |show|
        if show.linked?
          all_linked = show.event_linkage.shows.pluck(:id)
          if (all_linked - show_ids).any?
            summary[:warnings] << "Some linked events will not be transferred and the linkage will be broken"
            break
          end
        end
      end

      summary
    end

    # Only allow a list of trusted parameters through.
    def show_params
      permitted = params.require(:show).permit(:event_type, :secondary_name, :date_and_time, :poster, :remove_poster, :production_id, :location_id,
                                               :event_frequency, :recurrence_pattern, :recurrence_end_type, :recurrence_start_datetime, :recurrence_custom_end_date,
                                               :recurrence_edit_scope, :recurrence_group_id, :casting_enabled, :casting_source, :is_online, :online_location_info,
                                               :public_profile_visible, :use_custom_roles, :call_time, :call_time_enabled, :attendance_enabled,
                                               show_links_attributes: %i[id url text _destroy])

      # If is_online is true, clear location_id; if false, clear online_location_info
      if [ "1", "true", true ].include?(permitted[:is_online])
        permitted[:location_id] = nil
        permitted[:is_online] = true
      else
        permitted[:online_location_info] = nil
        permitted[:is_online] = false
      end

      # Handle public_profile_visible: empty string means nil (use default), otherwise convert to boolean
      if permitted[:public_profile_visible].present?
        permitted[:public_profile_visible] = permitted[:public_profile_visible] == "true"
      else
        permitted[:public_profile_visible] = nil
      end

      # Handle casting_source override: if clear_casting_source is set, clear casting_source to inherit from production
      if params[:clear_casting_source] == "1"
        permitted[:casting_source] = nil
      end

      permitted
    end

    # Copy custom roles from one show to another (used when duplicating shows with custom roles)
    def copy_custom_roles_from(source_show, target_show)
      source_show.custom_roles.each do |source_role|
        new_role = target_show.custom_roles.create!(
          name: source_role.name,
          position: source_role.position,
          restricted: source_role.restricted,
          production: @production
        )

        # Copy eligibilities if the role is restricted
        if source_role.restricted?
          source_role.role_eligibilities.each do |eligibility|
            new_role.role_eligibilities.create!(
              member_type: eligibility.member_type,
              member_id: eligibility.member_id
            )
          end
        end
      end
    end

    # Send cancellation notification emails to cast members
    # role_categories: optional array of category strings to filter by (e.g., ["performing", "technical"])
    def send_cancellation_notifications(shows, email_subject, email_body, role_categories = nil)
      # Filter out past shows - no need to notify about cancellation of past events
      shows = shows.select { |show| show.date_and_time >= Time.current }
      return if shows.empty?

      # Collect all unique people from all shows
      all_person_ids = Set.new

      shows.each do |show|
        # Build base query for assignments
        assignments = show.show_person_role_assignments

        # Filter by role categories if specified
        if role_categories.present?
          assignments = assignments.joins(:role).where(roles: { category: role_categories })
        end

        # People directly assigned
        assignments.where(assignable_type: "Person").pluck(:assignable_id).each do |id|
          all_person_ids << id
        end

        # People in groups assigned
        group_ids = assignments.where(assignable_type: "Group").pluck(:assignable_id)
        GroupMembership.where(group_id: group_ids).pluck(:person_id).each do |id|
          all_person_ids << id
        end
      end

      return if all_person_ids.empty?

      # Get people with user accounts (they can receive emails)
      people = Person.where(id: all_person_ids.to_a).includes(:user).select { |p| p.user.present? }

      # Create batch if sending to multiple people
      email_batch = nil
      if people.size > 1
        email_batch = EmailBatch.create!(
          user: Current.user,
          subject: email_subject || ContentTemplateService.render_subject("show_canceled", { production_name: @production.name }),
          recipient_count: people.size,
          sent_at: Time.current
        )
      end

      messages_sent = 0
      emails_sent = 0

      people.each do |person|
        # If email_body is provided, personalize it; otherwise let the service use the template
        personalized_body = email_body&.gsub("[Recipient Name]", person.name)

        result = ShowNotificationService.send_cancellation_notification(
          person: person,
          show: shows.first, # Use first show for subject line context
          production: @production,
          sender: Current.user,
          body: personalized_body,
          subject: email_subject,
          email_batch_id: email_batch&.id
        )
        messages_sent += result[:messages_sent]
        emails_sent += result[:emails_sent]
      end

      Rails.logger.info "[Shows] Sent cancellation: #{messages_sent} messages, #{emails_sent} emails"
    end

    # Infer recurrence pattern from a series of shows
    def infer_recurrence_pattern(shows)
      return nil if shows.length < 2

      # Calculate average days between shows
      days_between = []
      shows.each_cons(2) do |a, b|
        days_between << (b.date_and_time.to_date - a.date_and_time.to_date).to_i
      end

      avg_days = days_between.sum / days_between.length.to_f

      # Determine pattern based on average days
      case avg_days
      when 0..2
        "daily"
      when 5..9
        "weekly"
      when 12..16
        "biweekly"
      when 25..35
        # Check if it's same date of month (monthly_date) or same week/day (monthly_week)
        # For now, default to monthly_date
        "monthly_date"
      else
        "weekly" # Default fallback
      end
    end

    # Generate recurring dates for extending a series
    def generate_recurring_dates(start_datetime, pattern, end_date)
      dates = [ start_datetime ]
      current = start_datetime

      # Store initial values for monthly_week pattern
      initial_day_of_week = start_datetime.wday
      initial_week_of_month = (start_datetime.day - 1) / 7 + 1

      while current < end_date.end_of_day
        next_date = case pattern
        when "daily"
          current + 1.day
        when "weekly"
          current + 1.week
        when "biweekly"
          current + 2.weeks
        when "monthly_date"
          current + 1.month
        when "monthly_week"
          # Same week and day of month
          next_month = current + 1.month
          first_of_month = next_month.beginning_of_month
          days_until_target_day = (initial_day_of_week - first_of_month.wday) % 7
          first_occurrence = first_of_month + days_until_target_day.days
          target_date = first_occurrence + (initial_week_of_month - 1).weeks
          target_date.change(hour: start_datetime.hour, min: start_datetime.min, sec: start_datetime.sec)
        else
          current + 1.week
        end

        break if next_date > end_date.end_of_day
        dates << next_date
        current = next_date
      end

      dates
    end
  end
end
