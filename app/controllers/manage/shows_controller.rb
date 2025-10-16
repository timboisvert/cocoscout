class Manage::ShowsController < Manage::ManageController
  before_action :set_production, except: %i[ assign_person_to_role remove_person_from_role ]
  before_action :set_show, only: %i[ cast edit update destroy cancel uncancel assign_person_to_role remove_person_from_role ]
  before_action :ensure_user_is_manager, except: %i[ index ]

  def index
    # Store the shows filter
    @filter = (params[:filter] || session[:shows_filter] || "upcoming")
    session[:shows_filter] = @filter

    # Get the shows using the shows filter
    @shows = @production.shows

    case @filter
    when "past"
      @shows = @shows.where("shows.date_and_time <= ?", Time.current).order("shows.date_and_time DESC")
    else
      @filter = "upcoming"
      @shows = @shows.where("shows.date_and_time > ?", Time.current).order("shows.date_and_time ASC")
    end
  end

  def calendar
    # Get all shows/events for the production, including canceled ones
    @shows = @production.shows.order(:date_and_time)

    # Group shows by month for calendar display
    @shows_by_month = @shows.group_by { |show| show.date_and_time.beginning_of_month }
  end

  def cast
  end

  def new
    @show = @production.shows.new

    # if params[:duplicate].present?
    #   original = @production.shows.find_by(id: params[:duplicate])
    #   if original.present?
    #     @show.date_and_time = original.date_and_time
    #     @show.secondary_name = original.secondary_name
    #     @show.location = original.location
    #   end
    # end
  end

  def edit
  end

  def create
    if params[:show][:event_frequency] == "recurring"
      create_recurring_events
    else
      @show = Show.new(show_params)
      @show.production = @production

      if @show.save
        redirect_to manage_production_shows_path(@production), notice: "Show was successfully created"
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def create_recurring_events
    start_datetime = DateTime.parse(params[:show][:recurrence_start_datetime])
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
        current_datetime = current_datetime + 1.month
      when "monthly_week"
        datetimes << current_datetime
        # Move to next month, then find the same week and day
        next_month = current_datetime + 1.month
        # Find the first occurrence of the target day in the next month
        first_of_month = next_month.beginning_of_month
        days_until_target_day = (initial_day_of_week - first_of_month.wday) % 7
        first_occurrence = first_of_month + days_until_target_day.days
        # Add weeks to get to the target week
        current_datetime = first_occurrence + (initial_week_of_month - 1).weeks
      when "weekdays"
        if current_datetime.wday.between?(1, 5) # Monday to Friday
          datetimes << current_datetime
        end
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
        updated_count = 0

        @show.recurrence_group.each do |show|
          if show.update(update_params)
            updated_count += 1
          end
        end

        redirect_to manage_production_shows_path(@production),
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

      if @show.update(update_params)
        redirect_to manage_production_shows_path(@production),
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

    # Parse new recurrence parameters
    start_datetime = DateTime.parse(params[:show][:recurrence_start_datetime])
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
        current_datetime = current_datetime + 1.month
      when "monthly_week"
        datetimes << current_datetime
        # Move to next month, then find the same week and day
        next_month = current_datetime + 1.month
        # Find the first occurrence of the target day in the next month
        first_of_month = next_month.beginning_of_month
        days_until_target_day = (initial_day_of_week - first_of_month.wday) % 7
        first_occurrence = first_of_month + days_until_target_day.days
        # Add weeks to get to the target week
        current_datetime = first_occurrence + (initial_week_of_month - 1).weeks
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
    @show.update!(canceled: true)
    redirect_to manage_production_shows_path(@production), notice: "Show was successfully canceled", status: :see_other
  end

  def uncancel
    @show.update!(canceled: false)
    redirect_to manage_production_shows_path(@production), notice: "Show was successfully uncanceled", status: :see_other
  end

  def destroy
    @show.destroy!
    redirect_to manage_production_shows_path(@production), notice: "Show was successfully deleted", status: :see_other
  end

  def assign_person_to_role
    # Get the person and the role
    person = Person.find(params[:person_id])
    role = Role.find(params[:role_id])

    # If this role already has someone in it for this show, remove the assignment
    existing_assignments = @show.show_person_role_assignments.where(role: role)
    existing_assignments.destroy_all if existing_assignments.any?

    # Make the assignment
    assignment = @show.show_person_role_assignments.find_or_initialize_by(person: person, role: role)
    assignment.save!

    # Generate the HTML to return
    cast_members_html = render_to_string(partial: "manage/shows/cast_members_list", locals: { show: @show })
    roles_html = render_to_string(partial: "manage/shows/roles_list", locals: { show: @show })
    render json: { cast_members_html: cast_members_html, roles_html: roles_html }
  end

  def remove_person_from_role
    assignment = @show.show_person_role_assignments.find(params[:assignment_id])
    assignment.destroy! if assignment

    # Generate the HTML to return
    cast_members_html = render_to_string(partial: "manage/shows/cast_members_list", locals: { show: @show })
    roles_html = render_to_string(partial: "manage/shows/roles_list", locals: { show: @show })
    render json: { cast_members_html: cast_members_html, roles_html: roles_html }
  end

  private
    def set_production
      @production = Current.production_company.productions.find(params.expect(:production_id))
    end

    def set_show
      @show = Show.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def show_params
      params.require(:show).permit(:event_type, :secondary_name, :date_and_time, :poster, :production_id, :location_id,
        :event_frequency, :recurrence_pattern, :recurrence_end_type, :recurrence_start_datetime, :recurrence_custom_end_date,
        :recurrence_edit_scope, :recurrence_group_id,
        show_links_attributes: [ :id, :url, :_destroy ])
    end
end
