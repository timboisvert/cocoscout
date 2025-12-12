# frozen_string_literal: true

module Manage
  class ShowsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_show, only: %i[show edit update destroy cancel cancel_show delete_show uncancel link_show unlink_show]
    before_action :ensure_user_is_manager, except: %i[index show]

    def index
      # Store the shows filter
      @filter = params[:filter] || session[:shows_filter] || "upcoming"
      session[:shows_filter] = @filter

      # Handle event type filter (show, rehearsal, meeting, class, workshop) - checkboxes
      @event_type_filter = params[:event_type] ? params[:event_type].split(",") : EventTypes.all

      # Get the shows using the shows filter, eager load location to avoid N+1
      @shows = @production.shows.includes(:location)

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
    end

    def show
      # Preload data for the cast_card partial to avoid N+1 queries
      # Use available_roles which respects show.use_custom_roles
      @roles = @show.available_roles.to_a
      @roles_count = @roles.size

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
      @open_vacancies = @show.role_vacancies.open.includes(:role).to_a
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

    def new
      @show = @production.shows.new

      # Set default casting_enabled based on event_type from config
      @show.casting_enabled = EventTypes.casting_enabled_default(@show.event_type || "show")

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

      # Create shows for each datetime
      created_count = 0
      datetimes.each do |datetime|
        show = Show.new(
          event_type: params[:show][:event_type],
          secondary_name: params[:show][:secondary_name],
          location_id: params[:show][:location_id],
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

          redirect_to manage_production_show_path(@production, @show),
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
          redirect_to manage_production_show_path(@production, @show),
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
    end

    def cancel_show
      scope = params[:scope] || "this"
      event_label = @show.event_type.titleize

      if scope == "all" && @show.recurring?
        # Cancel all occurrences in the recurrence group
        count = @show.recurrence_group.update_all(canceled: true)
        redirect_to manage_production_shows_path(@production),
                    notice: "Successfully canceled #{count} #{event_label.pluralize.downcase}",
                    status: :see_other
      else
        # Cancel just this occurrence
        @show.update!(canceled: true)
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
            redirect_url: edit_manage_production_show_path(@production, @show, anchor: "tab-5")
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
            redirect_url: edit_manage_production_show_path(@production, @show, anchor: "tab-5")
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
        redirect_url: edit_manage_production_show_path(@production, @show, anchor: "tab-5")
      }
    end

    def destroy
      # Legacy destroy action - redirects to new cancel page
      redirect_to cancel_manage_production_show_path(@production, @show)
    end

    private

    def set_production
      if Current.organization
        @production = Current.organization.productions.find(params[:production_id])
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

    # Only allow a list of trusted parameters through.
    def show_params
      permitted = params.require(:show).permit(:event_type, :secondary_name, :date_and_time, :poster, :remove_poster, :production_id, :location_id,
                                               :event_frequency, :recurrence_pattern, :recurrence_end_type, :recurrence_start_datetime, :recurrence_custom_end_date,
                                               :recurrence_edit_scope, :recurrence_group_id, :casting_enabled, :is_online, :online_location_info,
                                               :public_profile_visible, :use_custom_roles,
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
  end
end
