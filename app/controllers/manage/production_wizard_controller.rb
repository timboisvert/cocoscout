# frozen_string_literal: true

module Manage
  class ProductionWizardController < Manage::ManageController
    before_action :ensure_user_is_global_manager
    # Stop a Producer-plan org at the door with the upgrade pitch instead of
    # letting them walk all seven steps into a validation wall at create.
    before_action :enforce_free_production_limit, only: %i[name create_production]
    before_action :load_wizard_state

    # How a paying production gets its payout calculation: pick one the org
    # already has, set up a new one right after the production is created, or
    # leave it for later.
    PAY_CHOICES = %w[existing new later].freeze

    # Marker returned by apply_wizard_pay_choice! when the calculation is to be
    # built in the payout-calculation wizard once the production exists.
    NEW_CALCULATION = :new_calculation

    # Step 1: Name - What's the production called?
    def name
      @wizard_state[:name] ||= ""
      @wizard_state[:description] ||= ""
    end

    def save_name
      @wizard_state[:name] = params[:name]&.strip
      @wizard_state[:description] = params[:description]&.strip
      # Optional "what kind of production" — only allowlisted genres stick.
      @wizard_state[:genre] = ProductionGenres.keys.include?(params[:genre].to_s) ? params[:genre].to_s : nil

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
        @wizard_state.delete(:logo_data)
        @wizard_state.delete(:logo_filename)
        @wizard_state.delete(:logo_content_type)
        save_wizard_state
        redirect_to manage_productions_wizard_casting_path and return
      end

      # Store logo data directly in cache (shared across web servers)
      if params[:logo].present?
        @wizard_state[:logo_data] = Base64.strict_encode64(params[:logo].read)
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
      source = params[:casting_source] || "talent_pool"
      @wizard_state[:casting_source] = source
      @wizard_state[:casting_enabled] = (source != "none")

      # No casting means no roles, no lineup, nobody to pay: skip straight on.
      if source == "none"
        @wizard_state[:casting_mode] = "role_based"
        @wizard_state[:has_roles] = "no"
        @wizard_state[:roles] = []
        @wizard_state[:pays_performers] = "no"
        clear_pay_choice
        save_wizard_state
        redirect_to manage_productions_wizard_shows_path and return
      end

      save_wizard_state
      redirect_to manage_productions_wizard_casting_style_path
    end

    # Step 3b: Casting style - fill named roles, or build a running order of acts?
    def casting_style
      @wizard_state[:casting_mode] ||= "role_based"
    end

    def save_casting_style
      mode = params[:casting_mode].to_s
      mode = "role_based" unless Production.casting_modes.key?(mode)
      # Break rows only make sense in a lineup — drop them if the mode flips back.
      if mode == "role_based" && @wizard_state[:roles].present?
        @wizard_state[:roles] = @wizard_state[:roles].reject { |r| (r[:category] || r["category"]) == Role::BREAK_CATEGORY }
      end
      @wizard_state[:casting_mode] = mode
      save_wizard_state
      redirect_to manage_productions_wizard_roles_path
    end

    # Step 4: Roles - Define positions to fill (or the lineup, in an act-based production)
    def roles
      @wizard_state[:has_roles] ||= nil
      @wizard_state[:roles] ||= []
    end

    def save_roles
      # Blank rows are dropped by parse_roles; a "yes" with nothing in it (or an
      # act-mode lineup left empty) is stored as no roles at all.
      roles = params[:has_roles] == "yes" ? parse_roles(params[:roles]) : []
      @wizard_state[:roles] = roles
      @wizard_state[:has_roles] = roles.any? ? "yes" : "no"

      save_wizard_state
      redirect_to(pay_step_available? ? manage_productions_wizard_pay_path : manage_productions_wizard_shows_path)
    end

    # Step 4b: Pay - will performers be paid? (Money is a paid feature; the step
    # only exists for orgs that have it.)
    def pay
      redirect_to manage_productions_wizard_shows_path and return unless pay_step_available?

      @wizard_state[:pays_performers] ||= "no"
      load_pay_step_data
    end

    def save_pay
      redirect_to manage_productions_wizard_shows_path and return unless pay_step_available?

      @wizard_state[:pays_performers] = params[:pays_performers] == "yes" ? "yes" : "no"
      clear_pay_choice

      if @wizard_state[:pays_performers] == "yes"
        choice = params[:pay_choice].to_s
        choice = "" if choice == "existing" && org_payout_calculations.none?
        @wizard_state[:pay_choice] = choice if PAY_CHOICES.include?(choice)

        case choice
        when "existing"
          calculation_id = params[:payout_scheme_id].presence
          if calculation_id && org_payout_calculations.exists?(id: calculation_id)
            @wizard_state[:payout_scheme_id] = calculation_id.to_i
          else
            @pay_error = "Choose one of your payout calculations, or set up a new one."
          end
        when "new", "later"
          # Nothing more to store: "new" sends them into the calculation wizard
          # right after create; "later" leaves it for the production's Pay tab.
        else
          @pay_error = "Tell us whether to use an existing calculation or set up a new one."
        end
      end

      if @pay_error
        load_pay_step_data
        render :pay, status: :unprocessable_entity and return
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
        @wizard_state[:recurring_week_ordinal] = params[:recurring][:week_ordinal]
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

      pay_outcome = nil
      ActiveRecord::Base.transaction do
        # Create the production
        @production = Current.organization.productions.new(
          name: @wizard_state[:name],
          description: @wizard_state[:description],
          genre: @wizard_state[:genre].presence,
          casting_source: @wizard_state[:casting_source] || "talent_pool",
          casting_mode: wizard_casting_mode,
          # "Will performers be paid?" — only asked on a paid plan; otherwise
          # the production keeps the default (on) until someone says otherwise.
          pays_performers: !(pay_step_available? && @wizard_state[:pays_performers] == "no"),
          casting_setup_completed: true
        )

        # Attach logo if provided (stored as base64 in cache)
        if @wizard_state[:logo_data].present?
          @production.logo.attach(
            io: StringIO.new(Base64.strict_decode64(@wizard_state[:logo_data])),
            filename: @wizard_state[:logo_filename],
            content_type: @wizard_state[:logo_content_type]
          )
        end

        unless @production.save
          flash.now[:alert] = @production.errors.full_messages.join(", ")
          render :review, status: :unprocessable_entity and return
        end

        # Create roles (the lineup, in order, for an act-based production —
        # break rows come through as category "break")
        if @wizard_state[:roles].present?
          @wizard_state[:roles].each_with_index do |role_data, index|
            category = role_data[:category] || role_data["category"] || "performing"
            category = "performing" if category == Role::BREAK_CATEGORY && !@production.act_based?
            @production.roles.create!(
              name: role_data[:name] || role_data["name"],
              quantity: (role_data[:quantity] || role_data["quantity"] || 1).to_i,
              category: category,
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
              casting_enabled: @wizard_state.fetch(:casting_enabled, true)
            )
          end
        end

        # Pay: give the production its payout calculation — an existing one now,
        # or a new one built in the calculation wizard right after this.
        # (After the shows, so the calculation reaches back to the first night.)
        pay_outcome = apply_wizard_pay_choice!
      end

      # Clear wizard state
      clear_wizard_state

      # Set production in session
      session[:current_production_id_for_organization] ||= {}
      session[:current_production_id_for_organization]["#{Current.user&.id}_#{Current.organization&.id}"] = @production.id

      # Turn on the "here's what to do next" panel on the manage home page.
      Current.user.activate_guide!(:production_next_steps)

      if pay_outcome == NEW_CALCULATION
        redirect_to manage_money_payout_calculation_wizard_start_path(
                      production_id: @production.id,
                      return_to: edit_manage_production_path(@production, anchor: "tab-6")
                    ),
                    notice: "#{@production.name} is ready — now set up how its performers are paid."
      else
        redirect_to manage_path, notice: "#{@production.name} has been created!"
      end
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      render :review, status: :unprocessable_entity
    end

    def cancel
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

    # "role_based" or "act_based" — whatever the casting-style step stored,
    # falling back to roles.
    def wizard_casting_mode
      mode = @wizard_state[:casting_mode].to_s
      Production.casting_modes.key?(mode) ? mode : "role_based"
    end

    def act_based_wizard?
      wizard_casting_mode == "act_based"
    end
    helper_method :act_based_wizard?

    # The pay step exists only for orgs with the Money feature, and only when
    # the production is cast at all.
    def pay_step_available?
      @wizard_state[:casting_source] != "none" && Current.organization.feature_available?(:money)
    end
    helper_method :pay_step_available?

    def org_payout_calculations
      Current.organization.payout_schemes.active
    end

    def clear_pay_choice
      @wizard_state.delete(:pay_choice)
      @wizard_state.delete(:payout_scheme_id)
    end

    def load_pay_step_data
      @payout_calculations = org_payout_calculations.order(:name).to_a
    end

    # Runs inside the create transaction. Makes an existing calculation the
    # production's own; returns NEW_CALCULATION when one is to be built in the
    # calculation wizard right after create; nil otherwise.
    def apply_wizard_pay_choice!
      return nil unless @wizard_state[:pays_performers] == "yes"

      case @wizard_state[:pay_choice]
      when "existing"
        calculation = org_payout_calculations.find_by(id: @wizard_state[:payout_scheme_id])
        calculation&.make_production_scheme!(@production)
        nil
      when "new"
        NEW_CALCULATION
      end
    end

    def parse_roles(roles_params)
      return [] if roles_params.blank?

      allowed = act_based_wizard? ? Role::CATEGORIES : (Role::CATEGORIES - [ Role::BREAK_CATEGORY ])

      roles_params.values.map do |role|
        next if role[:name].blank?
        category = role[:category].to_s
        category = "performing" unless allowed.include?(category)
        # An act (or an intermission) is one thing in the running order.
        quantity = act_based_wizard? ? 1 : [ (role[:quantity] || 1).to_i, 1 ].max
        {
          name: role[:name].to_s.strip,
          quantity: quantity,
          category: category
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
      week_ordinal = recurring_params[:week_ordinal].to_i
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

      # For monthly with explicit week ordinal, jump to the correct week of month
      if frequency == "monthly" && week_ordinal > 0
        target = nth_weekday_of_month(start_date.year, start_date.month, day_of_week, week_ordinal)
        target = nth_weekday_of_month((start_date >> 1).year, (start_date >> 1).month, day_of_week, week_ordinal) if target < start_date
        current_date = target
      end

      count.times do
        datetime = Time.zone.parse("#{current_date} #{time_str}")
        shows << {
          event_type: event_type,
          date_and_time: datetime.strftime("%Y-%m-%dT%H:%M"),
          location_id: location_id,
          is_online: false
        }

        case frequency
        when "weekly"
          current_date += 1.week
        when "biweekly"
          current_date += 2.weeks
        when "monthly"
          if week_ordinal > 0
            next_month = current_date >> 1
            current_date = nth_weekday_of_month(next_month.year, next_month.month, day_of_week, week_ordinal)
          else
            current_date += 1.month
            until current_date.wday == day_of_week
              current_date += 1.day
            end
          end
        end
      end

      shows
    end

    def nth_weekday_of_month(year, month, wday, ordinal)
      first = Date.new(year, month, 1)
      first_occurrence = first + ((wday - first.wday + 7) % 7)

      if ordinal >= 5
        # "Last" occurrence
        candidate = first_occurrence + 4.weeks
        candidate.month == month ? candidate : candidate - 1.week
      else
        first_occurrence + (ordinal - 1).weeks
      end
    end
  end
end
