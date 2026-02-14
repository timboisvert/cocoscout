# frozen_string_literal: true

module Manage
  class ProductionWizardController < Manage::ManageController
    before_action :ensure_user_is_global_manager
    before_action :load_wizard_state

    # Step 1: Name - What's the production called?
    def name
      @wizard_state[:name] ||= ""
      @wizard_state[:description] ||= ""
    end

    def save_name
      @wizard_state[:name] = params[:name]&.strip
      @wizard_state[:description] = params[:description]&.strip

      if @wizard_state[:name].blank?
        flash.now[:alert] = "Please enter a production name"
        render :name, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_productions_wizard_logo_path
    end

    # Step 2: Logo - Add a visual identity
    def logo
      # Logo is optional, just show the form
    end

    def save_logo
      # Handle skip
      if params[:skip] == "true"
        @wizard_state[:skip_logo] = true
        save_wizard_state
        redirect_to manage_productions_wizard_casting_path and return
      end

      # Store logo in temporary location if uploaded
      if params[:logo].present?
        # Store the uploaded file temporarily
        @wizard_state[:logo_temp_path] = store_temp_file(params[:logo])
        @wizard_state[:logo_filename] = params[:logo].original_filename
        @wizard_state[:logo_content_type] = params[:logo].content_type
      end

      save_wizard_state
      redirect_to manage_productions_wizard_casting_path
    end

    # Step 3: Casting - How do you cast your shows?
    def casting
      @wizard_state[:casting_source] ||= "talent_pool"
    end

    def save_casting
      @wizard_state[:casting_source] = params[:casting_source] || "talent_pool"
      save_wizard_state
      redirect_to manage_productions_wizard_roles_path
    end

    # Step 4: Roles - Define positions to fill
    def roles
      @wizard_state[:has_roles] ||= nil
      @wizard_state[:role_preset] ||= nil
      @wizard_state[:roles] ||= []
    end

    def save_roles
      @wizard_state[:has_roles] = params[:has_roles]

      # Handle roles based on selection
      if @wizard_state[:has_roles] == "yes"
        # Parse roles from form
        @wizard_state[:roles] = parse_roles(params[:roles])
      else
        @wizard_state[:roles] = []
      end

      save_wizard_state
      redirect_to manage_productions_wizard_shows_path
    end

    # Step 5: Shows - Do you know when your shows are?
    def shows
      @wizard_state[:has_shows] ||= nil
    end

    def save_shows
      @wizard_state[:has_shows] = params[:has_shows]

      save_wizard_state

      # If they have shows, go to schedule step; otherwise go to review
      if @wizard_state[:has_shows] == "yes"
        redirect_to manage_productions_wizard_schedule_path
      else
        @wizard_state[:shows] = []
        save_wizard_state
        redirect_to manage_productions_wizard_review_path
      end
    end

    # Step 6: Schedule - Add actual show dates (only if has_shows == yes)
    def schedule
      # Redirect to shows step if they haven't indicated they have shows
      unless @wizard_state[:has_shows] == "yes"
        redirect_to manage_productions_wizard_shows_path and return
      end

      @wizard_state[:schedule_type] ||= "single"
      @wizard_state[:shows] ||= []
      @locations = Current.organization.locations.order(:created_at)
      @default_location = @locations.find_by(default: true)
    end

    def save_schedule
      @wizard_state[:schedule_type] = params[:schedule_type]

      if @wizard_state[:schedule_type] == "repeating"
        # Generate shows from recurring settings
        @wizard_state[:shows] = generate_recurring_shows(params[:recurring])
        @wizard_state[:recurring_event_type] = params[:recurring][:event_type]
        @wizard_state[:recurring_frequency] = params[:recurring][:frequency]
        @wizard_state[:recurring_day_of_week] = params[:recurring][:day_of_week]
        @wizard_state[:recurring_time] = params[:recurring][:time]
        @wizard_state[:recurring_start_date] = params[:recurring][:start_date]
        @wizard_state[:recurring_count] = params[:recurring][:count].to_i
        @wizard_state[:recurring_location_id] = params[:recurring][:location_id]
      else
        # Parse single show from form
        @wizard_state[:shows] = parse_shows(params[:shows])
      end

      save_wizard_state
      redirect_to manage_productions_wizard_review_path
    end

    # Step 7: Review - Confirm and create
    def review
      @location = if @wizard_state[:shows].present? && @wizard_state[:shows].first[:location_id].present?
        Current.organization.locations.find_by(id: @wizard_state[:shows].first[:location_id])
      end
    end

    def create_production
      # Validate wizard state is present
      if @wizard_state[:name].blank?
        flash.now[:alert] = "Your wizard session has expired. Please start again."
        render :review, status: :unprocessable_entity and return
      end

      ActiveRecord::Base.transaction do
        # Create the production
        @production = Current.organization.productions.new(
          name: @wizard_state[:name],
          description: @wizard_state[:description],
          casting_source: @wizard_state[:casting_source] || "talent_pool",
          casting_setup_completed: true
        )

        # Attach logo if provided
        if @wizard_state[:logo_temp_path].present? && File.exist?(@wizard_state[:logo_temp_path])
          @production.logo.attach(
            io: File.open(@wizard_state[:logo_temp_path]),
            filename: @wizard_state[:logo_filename],
            content_type: @wizard_state[:logo_content_type]
          )
        end

        unless @production.save
          flash.now[:alert] = @production.errors.full_messages.join(", ")
          render :review, status: :unprocessable_entity and return
        end

        # Create roles
        if @wizard_state[:roles].present?
          @wizard_state[:roles].each_with_index do |role_data, index|
            @production.roles.create!(
              name: role_data[:name] || role_data["name"],
              quantity: (role_data[:quantity] || role_data["quantity"] || 1).to_i,
              category: role_data[:category] || role_data["category"] || "performing",
              position: index + 1,
              restricted: false
            )
          end
        end

        # Create shows
        if @wizard_state[:shows].present?
          @wizard_state[:shows].each do |show_data|
            next if show_data[:date_and_time].blank? && show_data["date_and_time"].blank?

            @production.shows.create!(
              event_type: show_data[:event_type] || show_data["event_type"] || "show",
              date_and_time: show_data[:date_and_time] || show_data["date_and_time"],
              duration_minutes: (show_data[:duration_minutes] || show_data["duration_minutes"]).presence&.to_i,
              location_id: show_data[:location_id] || show_data["location_id"],
              is_online: show_data[:is_online] || show_data["is_online"] || false,
              casting_enabled: true
            )
          end
        end
      end

      # Clean up temp files
      cleanup_temp_files

      # Clear wizard state
      clear_wizard_state

      # Set production in session
      session[:current_production_id_for_organization] ||= {}
      session[:current_production_id_for_organization]["#{Current.user&.id}_#{Current.organization&.id}"] = @production.id

      # Auto-dismiss welcome screen after creating first production
      Current.user.update(welcomed_production_at: Time.current) if Current.user.welcomed_production_at.nil?

      redirect_to manage_production_path(@production), notice: "#{@production.name} has been created!"
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      render :review, status: :unprocessable_entity
    end

    def cancel
      cleanup_temp_files
      clear_wizard_state
      redirect_to manage_productions_path, notice: "Production creation cancelled"
    end

    private

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
      "production_wizard:#{Current.user.id}:#{Current.organization.id}"
    end

    def store_temp_file(uploaded_file)
      temp_dir = Rails.root.join("tmp", "production_wizard_uploads")
      FileUtils.mkdir_p(temp_dir)

      temp_path = temp_dir.join("#{SecureRandom.uuid}_#{uploaded_file.original_filename}")
      File.open(temp_path, "wb") { |f| f.write(uploaded_file.read) }
      temp_path.to_s
    end

    def cleanup_temp_files
      if @wizard_state[:logo_temp_path].present? && File.exist?(@wizard_state[:logo_temp_path])
        File.delete(@wizard_state[:logo_temp_path])
      end
    rescue StandardError => e
      Rails.logger.error("Failed to cleanup temp file: #{e.message}")
    end

    def parse_custom_roles(roles_params)
      return [] if roles_params.blank?

      roles_params.values.map do |role|
        next if role[:name].blank?
        {
          name: role[:name],
          quantity: (role[:quantity] || 1).to_i,
          category: role[:category] || "performing"
        }
      end.compact
    end

    def parse_roles(roles_params)
      return [] if roles_params.blank?

      roles_params.values.map do |role|
        next if role[:name].blank?
        {
          name: role[:name],
          quantity: (role[:quantity] || 1).to_i,
          category: role[:category] || "performing"
        }
      end.compact
    end

    def parse_shows(shows_params)
      return [] if shows_params.blank?

      shows_params.values.map do |show|
        next if show[:date_and_time].blank?
        {
          event_type: show[:event_type] || "show",
          date_and_time: show[:date_and_time],
          location_id: show[:location_id],
          is_online: show[:is_online] == "true"
        }
      end.compact
    end

    def generate_recurring_shows(recurring_params)
      return [] if recurring_params.blank?

      event_type = recurring_params[:event_type] || "show"
      frequency = recurring_params[:frequency] || "weekly"
      day_of_week = recurring_params[:day_of_week].to_i
      time_str = recurring_params[:time] || "20:00"
      start_date = Date.parse(recurring_params[:start_date]) rescue Date.current
      count = (recurring_params[:count] || 8).to_i.clamp(1, 104)
      location_id = recurring_params[:location_id]

      shows = []

      # Find the first occurrence on the desired day of week
      current_date = start_date
      until current_date.wday == day_of_week
        current_date += 1.day
      end

      count.times do
        datetime = Time.zone.parse("#{current_date} #{time_str}")
        shows << {
          event_type: event_type,
          date_and_time: datetime.strftime("%Y-%m-%dT%H:%M"),
          location_id: location_id,
          is_online: false
        }

        # Advance to next occurrence
        case frequency
        when "weekly"
          current_date += 1.week
        when "biweekly"
          current_date += 2.weeks
        when "monthly"
          current_date += 1.month
          # Adjust to same day of week in next month
          until current_date.wday == day_of_week
            current_date += 1.day
          end
        end
      end

      shows
    end
  end
end
