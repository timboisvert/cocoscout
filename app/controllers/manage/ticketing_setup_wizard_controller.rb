# frozen_string_literal: true

module Manage
  class TicketingSetupWizardController < Manage::ManageController
    before_action :ensure_user_is_global_manager
    before_action :load_wizard_state, except: [ :start ]
    before_action :load_available_providers, only: [ :providers, :save_providers ]
    before_action :load_productions, only: [ :production, :save_production ]

    WIZARD_STEPS = %w[production providers strategy eventinfo venue images pricing review].freeze

    # ============================================
    # Start / Resume
    # ============================================

    def start
      # If editing an existing setup, load it
      if params[:setup_id].present?
        setup = Current.organization.production_ticketing_setups.find(params[:setup_id])
        initialize_wizard_from_setup(setup)
      else
        # New setup - clear any existing wizard state
        session[:ticketing_setup_wizard] = {
          step: "production",
          started_at: Time.current.iso8601
        }
      end

      redirect_to manage_ticketing_setup_wizard_production_path
    end

    # ============================================
    # Step 1: Production - Which production?
    # ============================================

    def production
      @wizard_state[:production_id] ||= nil
    end

    def save_production
      production_id = params[:production_id]

      if production_id.blank?
        flash.now[:alert] = "Please select a production"
        render :production, status: :unprocessable_entity and return
      end

      # Check if this production already has a setup
      existing = ProductionTicketingSetup.find_by(production_id: production_id)
      if existing && @wizard_state[:editing_setup_id] != existing.id
        flash.now[:alert] = "This production already has a ticketing setup. Edit it instead."
        render :production, status: :unprocessable_entity and return
      end

      @wizard_state[:production_id] = production_id.to_i
      @wizard_state[:step] = "providers"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_providers_path
    end

    # ============================================
    # Step 2: Providers - Which providers to use?
    # ============================================

    def providers
      @wizard_state[:provider_ids] ||= []
      @wizard_state[:provider_settings] ||= {}
    end

    def save_providers
      selected_ids = Array(params[:provider_ids]).map(&:to_i).reject(&:zero?)

      if selected_ids.empty?
        flash.now[:alert] = "Please select at least one ticketing provider"
        render :providers, status: :unprocessable_entity and return
      end

      @wizard_state[:provider_ids] = selected_ids

      # Store any provider-specific settings
      @wizard_state[:provider_settings] = {}
      selected_ids.each do |provider_id|
        if params.dig(:provider_settings, provider_id.to_s).present?
          @wizard_state[:provider_settings][provider_id] = params[:provider_settings][provider_id.to_s].permit!.to_h
        end
      end

      @wizard_state[:step] = "strategy"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_strategy_path
    end

    # ============================================
    # Step 3: Strategy - How to list shows?
    # ============================================

    def strategy
      @wizard_state[:listing_mode] ||= "all_shows"
      @wizard_state[:grouping_strategy] ||= "individual_events"

      # Check if any selected provider supports recurring events
      @supports_recurring = selected_providers.any? { |p| p.adapter.capabilities["supports_recurring"] }
    end

    def save_strategy
      @wizard_state[:listing_mode] = params[:listing_mode] || "all_shows"
      @wizard_state[:grouping_strategy] = params[:grouping_strategy] || "individual_events"

      # Validate
      unless %w[all_shows future_only selected_shows].include?(@wizard_state[:listing_mode])
        flash.now[:alert] = "Invalid listing mode"
        render :strategy, status: :unprocessable_entity and return
      end

      @wizard_state[:step] = "eventinfo"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_eventinfo_path
    end

    # ============================================
    # Step 4: Event Info - Default event details
    # ============================================

    def eventinfo
      @production = load_selected_production

      @wizard_state[:title_template] ||= "{production_name}"
      @wizard_state[:description] ||= @production&.description
      @wizard_state[:short_description] ||= nil
    end

    def save_eventinfo
      @wizard_state[:title_template] = params[:title_template]
      @wizard_state[:description] = params[:description]
      @wizard_state[:short_description] = params[:short_description]

      if @wizard_state[:description].blank?
        flash.now[:alert] = "Please provide an event description"
        @production = load_selected_production
        render :eventinfo, status: :unprocessable_entity and return
      end

      @wizard_state[:step] = "venue"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_venue_path
    end

    # ============================================
    # Step 5: Venue - Default venue info
    # ============================================

    def venue
      @production = load_selected_production

      # Pre-fill from production's shows if available
      first_show_with_location = @production&.shows&.find { |s| s.location.present? }
      if first_show_with_location&.location
        loc = first_show_with_location.location
        @wizard_state[:default_venue_name] ||= loc.name
        @wizard_state[:default_venue_address] ||= loc.address
        @wizard_state[:default_venue_city] ||= loc.city
        @wizard_state[:default_venue_postal_code] ||= loc.postal_code
        @wizard_state[:default_venue_country] ||= loc.country || "US"
      end

      @wizard_state[:online_event] ||= false
    end

    def save_venue
      @wizard_state[:online_event] = params[:online_event] == "1" || params[:online_event] == "true"

      unless @wizard_state[:online_event]
        @wizard_state[:default_venue_name] = params[:default_venue_name]
        @wizard_state[:default_venue_address] = params[:default_venue_address]
        @wizard_state[:default_venue_city] = params[:default_venue_city]
        @wizard_state[:default_venue_postal_code] = params[:default_venue_postal_code]
        @wizard_state[:default_venue_country] = params[:default_venue_country] || "US"

        # Venue name required for in-person events
        if @wizard_state[:default_venue_name].blank?
          flash.now[:alert] = "Please provide a venue name for in-person events"
          @production = load_selected_production
          render :venue, status: :unprocessable_entity and return
        end
      end

      @wizard_state[:step] = "images"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_images_path
    end

    # ============================================
    # Step 6: Images - Event imagery
    # ============================================

    def images
      @providers_with_image_specs = selected_providers.map do |provider|
        specs = case provider.provider_type
        when "eventbrite"
          { name: "Eventbrite", dimensions: "2160 x 1080 pixels", ratio: "2:1" }
        when "ticket_tailor"
          { name: "Ticket Tailor", dimensions: "1200 x 630 pixels", ratio: "1.9:1" }
        else
          { name: provider.name, dimensions: "1200 x 630 pixels", ratio: "1.9:1" }
        end
        { provider: provider, specs: specs }
      end
    end

    def save_images
      # Handle skip
      if params[:skip] == "true"
        @wizard_state[:skip_images] = true
        @wizard_state[:step] = "pricing"
        save_wizard_state
        redirect_to manage_ticketing_setup_wizard_pricing_path and return
      end

      # Store master image temporarily
      if params[:master_image].present?
        @wizard_state[:master_image_temp_path] = store_temp_file(params[:master_image])
        @wizard_state[:master_image_filename] = params[:master_image].original_filename
        @wizard_state[:master_image_content_type] = params[:master_image].content_type
      end

      @wizard_state[:step] = "pricing"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_pricing_path
    end

    # ============================================
    # Step 7: Pricing - Default ticket tiers
    # ============================================

    def pricing
      @wizard_state[:default_pricing_tiers] ||= [
        { "name" => "General Admission", "price_cents" => 2000, "description" => "", "quantity_per_show" => 100 }
      ]
      @wizard_state[:currency] ||= "USD"
    end

    def save_pricing
      @wizard_state[:currency] = params[:currency] || "USD"

      # Parse pricing tiers from form
      tiers = []
      if params[:tiers].present?
        params[:tiers].each do |_index, tier_params|
          next if tier_params[:name].blank?

          tiers << {
            "name" => tier_params[:name],
            "price_cents" => (tier_params[:price].to_f * 100).to_i,
            "description" => tier_params[:description],
            "quantity_per_show" => tier_params[:quantity].to_i
          }
        end
      end

      if tiers.empty?
        flash.now[:alert] = "Please add at least one ticket tier"
        render :pricing, status: :unprocessable_entity and return
      end

      @wizard_state[:default_pricing_tiers] = tiers
      @wizard_state[:step] = "review"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_review_path
    end

    # ============================================
    # Step 8: Review - Confirm and activate
    # ============================================

    def review
      @production = load_selected_production
      @providers = selected_providers
      @shows_count = calculate_shows_count
    end

    def create_setup
      @production = load_selected_production

      unless @production
        flash[:alert] = "Production not found"
        redirect_to manage_ticketing_setup_wizard_production_path and return
      end

      begin
        ActiveRecord::Base.transaction do
          # Create or update the setup
          @setup = if @wizard_state[:editing_setup_id]
            ProductionTicketingSetup.find(@wizard_state[:editing_setup_id])
          else
            ProductionTicketingSetup.new
          end

          @setup.assign_attributes(
            production: @production,
            organization: Current.organization,
            listing_mode: @wizard_state[:listing_mode],
            grouping_strategy: @wizard_state[:grouping_strategy],
            title_template: @wizard_state[:title_template],
            description: @wizard_state[:description],
            short_description: @wizard_state[:short_description],
            default_venue_name: @wizard_state[:default_venue_name],
            default_venue_address: @wizard_state[:default_venue_address],
            default_venue_city: @wizard_state[:default_venue_city],
            default_venue_postal_code: @wizard_state[:default_venue_postal_code],
            default_venue_country: @wizard_state[:default_venue_country],
            online_event: @wizard_state[:online_event],
            default_pricing_tiers: @wizard_state[:default_pricing_tiers],
            currency: @wizard_state[:currency],
            timezone: "America/New_York", # Could make this configurable
            status: params[:activate] == "true" ? "active" : "draft",
            created_by: current_user.person,
            wizard_completed_at: Time.current
          )

          if params[:activate] == "true"
            @setup.activated_at = Time.current
          end

          @setup.save!

          # Attach master image if provided
          if @wizard_state[:master_image_temp_path].present?
            attach_temp_file(@setup.master_image, @wizard_state[:master_image_temp_path],
                           @wizard_state[:master_image_filename], @wizard_state[:master_image_content_type])
          end

          # Create provider setups
          @wizard_state[:provider_ids].each do |provider_id|
            provider = TicketingProvider.find(provider_id)
            provider_setup = @setup.provider_setups.find_or_initialize_by(ticketing_provider: provider)
            provider_setup.enabled = true
            provider_setup.provider_settings = @wizard_state.dig(:provider_settings, provider_id) || {}
            provider_setup.save!
          end

          # Remove provider setups that were deselected
          @setup.provider_setups.where.not(ticketing_provider_id: @wizard_state[:provider_ids]).destroy_all
        end

        # Clear wizard state
        session.delete(:ticketing_setup_wizard)

        # Schedule initial sync if activated
        if @setup.status_active?
          @setup.schedule_initial_sync!
        end

        flash[:notice] = if @setup.status_active?
          "Ticketing setup created and activated! Events are being synced to your providers."
        else
          "Ticketing setup saved as draft. Activate it when you're ready to sync."
        end

        redirect_to manage_ticketing_index_path
      rescue StandardError => e
        Rails.logger.error "Ticketing setup wizard error: #{e.message}"
        flash.now[:alert] = "Error creating setup: #{e.message}"
        render :review, status: :unprocessable_entity
      end
    end

    def cancel
      session.delete(:ticketing_setup_wizard)
      redirect_to manage_ticketing_index_path, notice: "Ticketing setup cancelled"
    end

    private

    def load_wizard_state
      @wizard_state = (session[:ticketing_setup_wizard] || {}).with_indifferent_access

      if @wizard_state.blank?
        redirect_to manage_ticketing_setup_wizard_start_path and return
      end
    end

    def save_wizard_state
      session[:ticketing_setup_wizard] = @wizard_state.to_h
    end

    def load_available_providers
      @available_providers = Current.organization.ticketing_providers.active
    end

    def load_productions
      # Productions that don't already have a ticketing setup
      existing_setup_ids = ProductionTicketingSetup.where(organization: Current.organization).pluck(:production_id)
      @available_productions = Current.organization.productions
        .where.not(id: existing_setup_ids)
        .includes(:shows)
        .order(created_at: :desc)

      # Also include the one being edited if applicable
      if @wizard_state[:editing_setup_id]
        editing_production_id = ProductionTicketingSetup.find(@wizard_state[:editing_setup_id]).production_id
        @production_being_edited = Production.find(editing_production_id)
      end
    end

    def load_selected_production
      return nil unless @wizard_state[:production_id]

      Current.organization.productions.find_by(id: @wizard_state[:production_id])
    end

    def selected_providers
      return [] unless @wizard_state[:provider_ids].present?

      TicketingProvider.where(id: @wizard_state[:provider_ids])
    end

    def calculate_shows_count
      production = load_selected_production
      return 0 unless production

      case @wizard_state[:listing_mode]
      when "all_shows"
        production.shows.count
      when "future_only"
        production.shows.where("date_and_time >= ?", Time.current).count
      when "selected_shows"
        0 # Will be specified in per-show rules
      else
        0
      end
    end

    def initialize_wizard_from_setup(setup)
      session[:ticketing_setup_wizard] = {
        editing_setup_id: setup.id,
        production_id: setup.production_id,
        provider_ids: setup.provider_setups.pluck(:ticketing_provider_id),
        provider_settings: setup.provider_setups.each_with_object({}) do |ps, h|
          h[ps.ticketing_provider_id] = ps.provider_settings
        end,
        listing_mode: setup.listing_mode,
        grouping_strategy: setup.grouping_strategy,
        title_template: setup.title_template,
        description: setup.description,
        short_description: setup.short_description,
        default_venue_name: setup.default_venue_name,
        default_venue_address: setup.default_venue_address,
        default_venue_city: setup.default_venue_city,
        default_venue_postal_code: setup.default_venue_postal_code,
        default_venue_country: setup.default_venue_country,
        online_event: setup.online_event,
        default_pricing_tiers: setup.default_pricing_tiers,
        currency: setup.currency,
        step: "production",
        started_at: Time.current.iso8601
      }
    end

    def store_temp_file(uploaded_file)
      temp_path = Rails.root.join("tmp", "wizard_uploads", SecureRandom.uuid)
      FileUtils.mkdir_p(temp_path.dirname)
      File.binwrite(temp_path, uploaded_file.read)
      temp_path.to_s
    end

    def attach_temp_file(attachment, temp_path, filename, content_type)
      return unless File.exist?(temp_path)

      attachment.attach(
        io: File.open(temp_path),
        filename: filename,
        content_type: content_type
      )

      FileUtils.rm_f(temp_path)
    end
  end
end
