# frozen_string_literal: true

module Manage
  class ShowWizardController < Manage::ManageController
    before_action :set_production, except: [ :select_production, :save_production_selection ]
    before_action :check_production_access, except: [ :select_production, :save_production_selection ]
    before_action :ensure_user_is_manager, except: [ :select_production, :save_production_selection ]
    before_action :load_wizard_state, except: [ :select_production, :save_production_selection ]

    # Step 0: Select Production (when entering from org-level)
    def select_production
      @productions = Current.organization.productions.order(:name)
    end

    def save_production_selection
      production_id = params[:production_id]

      if production_id.blank?
        flash.now[:alert] = "Please select a production"
        @productions = Current.organization.productions.order(:name)
        render :select_production, status: :unprocessable_entity and return
      end

      production = Current.organization.productions.find_by(id: production_id)
      unless production
        flash.now[:alert] = "Production not found"
        @productions = Current.organization.productions.order(:name)
        render :select_production, status: :unprocessable_entity and return
      end

      # Redirect to the production-level wizard
      redirect_to manage_shows_wizard_path(production)
    end

    # Step 1: Event Type - What kind of event?
    def event_type
      # Handle duplication: pre-populate from existing show
      if params[:duplicate].present? && @wizard_state.blank?
        original_show = @production.shows.find_by(id: params[:duplicate])
        if original_show
          @wizard_state = {
            event_type: original_show.event_type,
            date_and_time: original_show.date_and_time,
            location_id: original_show.location_id,
            is_online: original_show.is_online,
            online_location_info: original_show.online_location_info,
            secondary_name: original_show.secondary_name,
            casting_enabled: original_show.casting_enabled,
            public_profile_visible: original_show.public_profile_visible,
            event_frequency: "single",
            duplicating_from: original_show.id
          }.with_indifferent_access
          save_wizard_state
          flash.now[:notice] = "Duplicating from: #{original_show.display_name}"
        end
      end

      @wizard_state[:event_type] ||= "show"
    end

    def save_event_type
      @wizard_state[:event_type] = params[:event_type]

      unless EventTypes.all.include?(@wizard_state[:event_type])
        flash.now[:alert] = "Please select an event type"
        render :event_type, status: :unprocessable_entity and return
      end

      # Set defaults based on event type
      @wizard_state[:casting_enabled] = EventTypes.casting_enabled_default(@wizard_state[:event_type])
      @wizard_state[:call_time_enabled] = EventTypes.call_time_enabled_default(@wizard_state[:event_type])

      save_wizard_state
      redirect_to manage_shows_wizard_schedule_path(@production)
    end

    # Step 2: Schedule - When is the event?
    def schedule
      @wizard_state[:event_frequency] ||= "single"
      @wizard_state[:date_and_time] ||= 1.week.from_now.change(hour: 19, min: 0)
    end

    def save_schedule
      @wizard_state[:event_frequency] = params[:event_frequency]
      @wizard_state[:date_and_time] = params[:date_and_time]
      @wizard_state[:recurrence_pattern] = params[:recurrence_pattern]
      @wizard_state[:recurrence_end_type] = params[:recurrence_end_type]
      @wizard_state[:recurrence_start_datetime] = params[:recurrence_start_datetime]
      @wizard_state[:recurrence_custom_end_date] = params[:recurrence_custom_end_date]

      if @wizard_state[:event_frequency] == "single"
        if @wizard_state[:date_and_time].blank?
          flash.now[:alert] = "Please select a date and time"
          render :schedule, status: :unprocessable_entity and return
        end
      else
        if @wizard_state[:recurrence_start_datetime].blank?
          flash.now[:alert] = "Please select a start date and time"
          render :schedule, status: :unprocessable_entity and return
        end
        if @wizard_state[:recurrence_pattern].blank?
          flash.now[:alert] = "Please select a repeat pattern"
          render :schedule, status: :unprocessable_entity and return
        end
        if @wizard_state[:recurrence_end_type].blank?
          flash.now[:alert] = "Please select a duration"
          render :schedule, status: :unprocessable_entity and return
        end
      end

      save_wizard_state
      redirect_to manage_shows_wizard_location_path(@production)
    end

    # Step 3: Location - Where is the event?
    def location
      @wizard_state[:is_online] ||= false
      @locations = Current.organization.locations.order(:created_at)

      # Set default location if available
      if @wizard_state[:location_id].blank?
        default_location = Current.organization.locations.find_by(default: true)
        @wizard_state[:location_id] = default_location&.id
      end
    end

    def save_location
      @wizard_state[:is_online] = params[:is_online] == "true"
      @wizard_state[:location_id] = params[:location_id]
      @wizard_state[:online_location_info] = params[:online_location_info]

      if !@wizard_state[:is_online] && @wizard_state[:location_id].blank?
        flash.now[:alert] = "Please select a location or mark as online"
        @locations = Current.organization.locations.order(:created_at)
        render :location, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_shows_wizard_details_path(@production)
    end

    # Step 4: Details - Additional info
    def details
      @wizard_state[:secondary_name] ||= ""
    end

    def save_details
      @wizard_state[:secondary_name] = params[:secondary_name]
      @wizard_state[:casting_enabled] = params[:casting_enabled] == "1"
      @wizard_state[:public_profile_visible] = params[:public_profile_visible] == "1"

      save_wizard_state
      redirect_to manage_shows_wizard_review_path(@production)
    end

    # Step 5: Review - Confirm and create
    def review
      @location = @wizard_state[:location_id].present? ? Current.organization.locations.find_by(id: @wizard_state[:location_id]) : nil
    end

    def create_show
      if @wizard_state[:event_frequency] == "recurring"
        create_recurring_events
      else
        create_single_event
      end
    end

    def cancel
      clear_wizard_state
      redirect_to manage_production_shows_path(@production), notice: "Show creation cancelled"
    end

    private

    def create_single_event
      @show = @production.shows.new(
        event_type: @wizard_state[:event_type],
        date_and_time: @wizard_state[:date_and_time],
        location_id: @wizard_state[:is_online] ? nil : @wizard_state[:location_id],
        is_online: @wizard_state[:is_online],
        online_location_info: @wizard_state[:online_location_info],
        secondary_name: @wizard_state[:secondary_name],
        casting_enabled: @wizard_state[:casting_enabled],
        public_profile_visible: @wizard_state[:public_profile_visible]
      )

      if @show.save
        clear_wizard_state
        redirect_to manage_production_shows_path(@production), notice: "Show was successfully created"
      else
        flash.now[:alert] = @show.errors.full_messages.join(", ")
        @location = @wizard_state[:location_id].present? ? Current.organization.locations.find_by(id: @wizard_state[:location_id]) : nil
        render :review, status: :unprocessable_entity
      end
    end

    def create_recurring_events
      start_datetime = Time.zone.parse(@wizard_state[:recurrence_start_datetime])
      pattern = @wizard_state[:recurrence_pattern]
      end_type = @wizard_state[:recurrence_end_type]

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
        Date.parse(@wizard_state[:recurrence_custom_end_date])
      else
        start_datetime.to_date + 3.months
      end

      dates = generate_recurring_dates(start_datetime, pattern, end_date)
      created_count = 0

      # Generate a shared recurrence_group_id for all shows in this series
      recurrence_group_id = SecureRandom.uuid

      dates.each do |date|
        show = @production.shows.new(
          event_type: @wizard_state[:event_type],
          date_and_time: date,
          location_id: @wizard_state[:is_online] ? nil : @wizard_state[:location_id],
          is_online: @wizard_state[:is_online],
          online_location_info: @wizard_state[:online_location_info],
          secondary_name: @wizard_state[:secondary_name],
          casting_enabled: @wizard_state[:casting_enabled],
          public_profile_visible: @wizard_state[:public_profile_visible],
          recurrence_group_id: recurrence_group_id,
          recurrence_pattern: pattern
        )
        created_count += 1 if show.save
      end

      clear_wizard_state
      redirect_to manage_production_shows_path(@production), notice: "#{created_count} recurring events were successfully created"
    end

    def generate_recurring_dates(start_datetime, pattern, end_date)
      dates = [ start_datetime ]
      current = start_datetime

      while current < end_date.end_of_day
        next_date = case pattern
        when "weekly"
          current + 1.week
        when "biweekly"
          current + 2.weeks
        when "monthly_date"
          current + 1.month
        when "monthly_week"
          # Same week and day of month
          next_month = current + 1.month
          week_of_month = (current.day - 1) / 7 + 1
          first_day = next_month.beginning_of_month
          first_weekday = first_day.beginning_of_week(:sunday) + current.wday.days
          first_weekday += 1.week if first_weekday < first_day
          first_weekday + (week_of_month - 1).weeks
        else
          current + 1.week
        end

        break if next_date > end_date.end_of_day
        dates << next_date
        current = next_date
      end

      dates
    end

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def load_wizard_state
      @wizard_state = Rails.cache.read(wizard_cache_key) || {}
      @wizard_state = @wizard_state.with_indifferent_access
    end

    def save_wizard_state
      Rails.cache.write(wizard_cache_key, @wizard_state.to_h, expires_in: 24.hours)
    end

    def clear_wizard_state
      Rails.cache.delete(wizard_cache_key)
    end

    def wizard_cache_key
      "show_wizard:#{Current.user.id}:#{@production.id}"
    end
  end
end
