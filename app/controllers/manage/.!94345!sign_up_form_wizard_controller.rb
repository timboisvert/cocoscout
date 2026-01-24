# frozen_string_literal: true

module Manage
  class SignUpFormWizardController < Manage::ManageController
    before_action :set_production, except: [ :select_production, :save_production_selection ]
    before_action :check_production_access, except: [ :select_production, :save_production_selection ]
    before_action :ensure_user_is_manager
    before_action :load_wizard_state, except: [ :select_production, :save_production_selection ]

    helper_method :generate_default_name

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
      redirect_to manage_signups_forms_wizard_path(production)
    end

    # Step 1: Scope - What type of sign-up form?
    def scope
      @wizard_state[:scope] ||= "single_event"
    end

    def save_scope
      @wizard_state[:scope] = params[:scope]

      unless %w[single_event repeated shared_pool].include?(@wizard_state[:scope])
        flash.now[:alert] = "Please select a registration scope"
        render :scope, status: :unprocessable_entity and return
      end

      save_wizard_state

      # If single_event or repeated, go to events selection; shared_pool skips to slots
      if @wizard_state[:scope] == "shared_pool"
        redirect_to manage_signups_forms_wizard_slots_path(@production)
      else
        redirect_to manage_signups_forms_wizard_events_path(@production)
      end
    end

    # Step 2: Events - Which shows does this form apply to?
    def events
      # Skip this step for shared_pool
      if @wizard_state[:scope] == "shared_pool"
        redirect_to manage_signups_forms_wizard_slots_path(@production)
        return
      end

      @wizard_state[:event_matching] ||= "all"
      @wizard_state[:event_type_filter] ||= []
      @wizard_state[:selected_show_ids] ||= []

      @shows = @production.shows.where(canceled: false)
                          .where("date_and_time >= ?", Time.current)
                          .order(:date_and_time)
      @event_types = EventTypes.for_select
    end

    def save_events
      @wizard_state[:event_matching] = params[:event_matching]

      case @wizard_state[:event_matching]
      when "event_types"
        @wizard_state[:event_type_filter] = params[:event_type_filter] || []
      when "manual"
        @wizard_state[:selected_show_ids] = params[:selected_show_ids] || []
      end

      # For single_event, must have exactly one show selected
      if @wizard_state[:scope] == "single_event"
        @wizard_state[:event_matching] = "manual" # Force manual selection for single_event
        if @wizard_state[:selected_show_ids].blank? || @wizard_state[:selected_show_ids].empty?
          flash.now[:alert] = "Please select a show for this sign-up form"
          @shows = @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current).order(:date_and_time)
          @event_types = EventTypes.for_select
          render :events, status: :unprocessable_entity and return
        end
      end

      save_wizard_state
      redirect_to manage_signups_forms_wizard_slots_path(@production)
    end

    # Step 3: Slots & Capacity - How are registration slots structured?
    def slots
      # Default slot_generation_mode based on scope - shared_pool doesn't have numbered/time_based
      if @wizard_state[:slot_generation_mode].blank?
        @wizard_state[:slot_generation_mode] = @wizard_state[:scope] == "shared_pool" ? "open_list" : "numbered"
      end
      @wizard_state[:slot_count] ||= 10
      @wizard_state[:slot_prefix] ||= "Slot"
      @wizard_state[:slot_capacity] ||= 1
      @wizard_state[:slot_start_time] ||= "09:00"
      @wizard_state[:slot_interval_minutes] ||= 5
      @wizard_state[:slot_names] ||= []
    end

    def save_slots
      @wizard_state[:slot_generation_mode] = params[:slot_generation_mode]
      @wizard_state[:slot_count] = params[:slot_count].to_i
      @wizard_state[:slot_prefix] = params[:slot_prefix]
      @wizard_state[:slot_capacity] = params[:slot_capacity].to_i
      @wizard_state[:slot_start_time] = params[:slot_start_time]
      @wizard_state[:slot_interval_minutes] = params[:slot_interval_minutes].to_i
      @wizard_state[:slot_names] = parse_slot_names(params[:slot_names])

      # Open List settings
      @wizard_state[:open_list_limit] = params[:open_list_limit]
      @wizard_state[:open_list_capacity] = params[:open_list_capacity].to_i

      # Validation
      if @wizard_state[:slot_generation_mode].blank?
        flash.now[:alert] = "Please choose how slots are structured"
        render :slots, status: :unprocessable_entity and return
      end

      case @wizard_state[:slot_generation_mode]
      when "numbered", "time_based"
        if @wizard_state[:slot_count] <= 0 || @wizard_state[:slot_count] > 100
          flash.now[:alert] = "Please enter a valid number of slots (1-100)"
          render :slots, status: :unprocessable_entity and return
        end
      when "named"
        if @wizard_state[:slot_names].empty?
          flash.now[:alert] = "Please enter at least one slot name"
          render :slots, status: :unprocessable_entity and return
        end
      when "open_list"
        if @wizard_state[:open_list_limit] != "unlimited" && @wizard_state[:open_list_capacity] <= 0
          flash.now[:alert] = "Please enter a valid capacity"
          render :slots, status: :unprocessable_entity and return
        end
      when "simple_capacity"
        if @wizard_state[:slot_count] <= 0
          flash.now[:alert] = "Please enter a valid total capacity"
          render :slots, status: :unprocessable_entity and return
        end
      end

      save_wizard_state
      redirect_to manage_signups_forms_wizard_rules_path(@production)
    end

    # Step 4: Rules - Registration limits, editing, cancellation
    def rules
      @wizard_state[:registrations_per_person] ||= 1
      # Default to auto_assign for waitlist (shared_pool) and open_list modes
      if @wizard_state[:slot_selection_mode].nil?
        is_waitlist_or_open_list = @wizard_state[:scope] == "shared_pool" || @wizard_state[:slot_generation_mode] == "open_list"
        @wizard_state[:slot_selection_mode] = is_waitlist_or_open_list ? "auto_assign" : "choose_slot"
      end
      @wizard_state[:require_login] = true if @wizard_state[:require_login].nil?
      @wizard_state[:allow_edit] = true if @wizard_state[:allow_edit].nil?
      @wizard_state[:allow_cancel] = false if @wizard_state[:allow_cancel].nil?
      @wizard_state[:show_registrations] = true if @wizard_state[:show_registrations].nil?
      @wizard_state[:edit_cutoff_days] ||= 0
      @wizard_state[:edit_cutoff_hours] ||= 0
      @wizard_state[:edit_cutoff_minutes] ||= 0
      @wizard_state[:cancel_cutoff_days] ||= 0
      @wizard_state[:cancel_cutoff_hours] ||= 0
      @wizard_state[:cancel_cutoff_minutes] ||= 0
      @wizard_state[:holdback_visible] = true if @wizard_state[:holdback_visible].nil?
    end

    def save_rules
      @wizard_state[:registrations_per_person] = params[:registrations_per_person].to_i
      @wizard_state[:slot_selection_mode] = params[:slot_selection_mode]
      @wizard_state[:require_login] = params[:require_login] == "1"
      @wizard_state[:allow_edit] = params[:allow_edit] == "1"
      @wizard_state[:allow_cancel] = params[:allow_cancel] == "1"
      @wizard_state[:show_registrations] = params[:show_registrations] == "1"

      # Queue settings (for admin_assigns mode)
      if params[:slot_selection_mode] == "admin_assigns"
        @wizard_state[:queue_limit] = params[:queue_limit].presence&.to_i
        @wizard_state[:queue_carryover] = params[:queue_carryover] == "1"
      end

      # Holdback settings
      @wizard_state[:enable_holdbacks] = params[:enable_holdbacks] == "1"
      if @wizard_state[:enable_holdbacks]
        @wizard_state[:holdback_interval] = params[:holdback_interval].to_i
        @wizard_state[:holdback_label] = params[:holdback_label]
        @wizard_state[:holdback_visible] = params[:holdback_visible] == "1"
      end

      # Edit cutoff settings (toggle OFF by default)
      @wizard_state[:edit_has_cutoff] = params[:edit_has_cutoff] == "1"
      if @wizard_state[:edit_has_cutoff]
        @wizard_state[:edit_cutoff_mode] = params[:edit_cutoff_mode]
        @wizard_state[:edit_cutoff_days] = params[:edit_cutoff_days].to_i
        @wizard_state[:edit_cutoff_hours] = params[:edit_cutoff_hours].to_i
        @wizard_state[:edit_cutoff_minutes] = params[:edit_cutoff_minutes].to_i
        # Handle "after" mode - store in separate fields for clarity
        if params[:edit_cutoff_mode] == "after_event"
          @wizard_state[:edit_cutoff_after_days] = params[:edit_cutoff_after_days].to_i
          @wizard_state[:edit_cutoff_after_hours] = params[:edit_cutoff_after_hours].to_i
          @wizard_state[:edit_cutoff_after_minutes] = params[:edit_cutoff_after_minutes].to_i
        end
      else
        @wizard_state[:edit_cutoff_mode] = nil
      end

      # Cancel cutoff settings (toggle OFF by default)
      @wizard_state[:cancel_has_cutoff] = params[:cancel_has_cutoff] == "1"
      if @wizard_state[:cancel_has_cutoff]
        @wizard_state[:cancel_cutoff_mode] = params[:cancel_cutoff_mode]
        @wizard_state[:cancel_cutoff_days] = params[:cancel_cutoff_days].to_i
        @wizard_state[:cancel_cutoff_hours] = params[:cancel_cutoff_hours].to_i
        @wizard_state[:cancel_cutoff_minutes] = params[:cancel_cutoff_minutes].to_i
        # Handle "after" mode
        if params[:cancel_cutoff_mode] == "after_event"
          @wizard_state[:cancel_cutoff_after_days] = params[:cancel_cutoff_after_days].to_i
          @wizard_state[:cancel_cutoff_after_hours] = params[:cancel_cutoff_after_hours].to_i
          @wizard_state[:cancel_cutoff_after_minutes] = params[:cancel_cutoff_after_minutes].to_i
        end
      else
        @wizard_state[:cancel_cutoff_mode] = nil
      end

      if @wizard_state[:registrations_per_person] <= 0
        flash.now[:alert] = "Registrations per person must be at least 1"
        render :rules, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_signups_forms_wizard_schedule_path(@production)
    end

    # Step 5: Schedule - When does registration open/close?
    def schedule
      @wizard_state[:schedule_mode] ||= "relative"
      @wizard_state[:opens_days_before] ||= 7
      @wizard_state[:closes_mode] ||= "event_start"
      @wizard_state[:closes_offset_value] ||= 2
      @wizard_state[:closes_offset_unit] ||= "hours"
      @wizard_state[:closes_before_after] ||= "after"
      # Only set default opens_at for non-waitlist scopes (waitlist defaults to "now")
      unless @wizard_state[:scope] == "shared_pool"
        @wizard_state[:opens_at] ||= 1.day.from_now.beginning_of_day
      end
      @wizard_state[:closes_at] ||= nil
    end

    def save_schedule
      @wizard_state[:schedule_mode] = params[:schedule_mode]

      if @wizard_state[:schedule_mode] == "immediate"
        # Opens immediately
        @wizard_state[:opens_at] = nil
        # Save closes settings for immediate mode too (days/hours/minutes)
        @wizard_state[:closes_mode] = params[:closes_mode] || "event_start"
        @wizard_state[:closes_offset_days] = params[:closes_offset_days].to_i
        @wizard_state[:closes_offset_hours] = params[:closes_offset_hours].to_i
        @wizard_state[:closes_minutes_offset] = params[:closes_minutes_offset].to_i
        @wizard_state[:closes_before_after] = params[:closes_before_after]
      elsif @wizard_state[:schedule_mode] == "relative"
        # Opens settings (days/hours/minutes before)
        @wizard_state[:opens_days_before] = params[:opens_days_before].to_i
        @wizard_state[:opens_hours_before] = params[:opens_hours_before].to_i
        @wizard_state[:opens_minutes_before] = params[:opens_minutes_before].to_i

        # Closes settings (days/hours/minutes before/after)
        @wizard_state[:closes_mode] = params[:closes_mode]
        @wizard_state[:closes_offset_days] = params[:closes_offset_days].to_i
        @wizard_state[:closes_offset_hours] = params[:closes_offset_hours].to_i
        @wizard_state[:closes_minutes_offset] = params[:closes_minutes_offset].to_i
        @wizard_state[:closes_before_after] = params[:closes_before_after]
      else
        @wizard_state[:opens_at] = params[:opens_at]
        @wizard_state[:closes_at] = params[:closes_at].presence
      end

      # Handle waitlist activation mode
      if params[:activation_mode].present?
        if params[:activation_mode] == "now"
          @wizard_state[:opens_at] = nil
        else
          @wizard_state[:opens_at] = params[:opens_at]
        end
      end

      # Handle hide registrations settings (only if show_registrations is enabled)
      if @wizard_state[:show_registrations]
        @wizard_state[:hide_registrations_mode] = params[:hide_registrations_mode] || "event_start"
        @wizard_state[:hide_registrations_offset_value] = params[:hide_registrations_offset_value].to_i
        @wizard_state[:hide_registrations_offset_unit] = params[:hide_registrations_offset_unit] || "hours"
      end

      save_wizard_state
      redirect_to manage_signups_forms_wizard_notifications_path(@production)
    end

    # Step 6: Notifications - Notify team when someone registers?
    def notifications
      @wizard_state[:notify_on_registration] = false if @wizard_state[:notify_on_registration].nil?
    end

    def save_notifications
      @wizard_state[:notify_on_registration] = params[:notify_on_registration] == "1"

      save_wizard_state
      redirect_to manage_signups_forms_wizard_review_path(@production)
    end

    # Step 7: Review - Summary of all settings
    def review
      # Load shows for display if needed
      if @wizard_state[:scope] == "single_event" && @wizard_state[:selected_show_ids].present?
        @selected_show = @production.shows.find_by(id: @wizard_state[:selected_show_ids].first)
      elsif @wizard_state[:event_matching] == "manual" && @wizard_state[:selected_show_ids].present?
        @selected_shows = @production.shows.where(id: @wizard_state[:selected_show_ids])
      end
    end

    def create_form
      ActiveRecord::Base.transaction do
        # For open_list mode, map open_list_capacity to slot_count (which is used as the single slot's capacity)
        slot_count = if @wizard_state[:slot_generation_mode] == "open_list"
                       if @wizard_state[:open_list_limit] == "unlimited"
                         999_999 # Effectively unlimited
                       else
                         @wizard_state[:open_list_capacity].to_i.clamp(1, 999_999)
                       end
        else
                       @wizard_state[:slot_count]
        end

        @sign_up_form = @production.sign_up_forms.new(
          name: params[:name].presence || generate_default_name,
          active: true,
          scope: @wizard_state[:scope],
          event_matching: @wizard_state[:event_matching],
          event_type_filter: @wizard_state[:event_type_filter],
          slot_generation_mode: @wizard_state[:slot_generation_mode],
          slot_count: slot_count,
          slot_prefix: @wizard_state[:slot_prefix],
          slot_capacity: @wizard_state[:slot_capacity],
          slot_start_time: @wizard_state[:slot_start_time],
          slot_interval_minutes: @wizard_state[:slot_interval_minutes],
          slot_names: @wizard_state[:slot_names],
          registrations_per_person: @wizard_state[:registrations_per_person],
          slot_selection_mode: @wizard_state[:slot_selection_mode],
          queue_limit: @wizard_state[:queue_limit],
          queue_carryover: @wizard_state[:queue_carryover] || false,
          require_login: @wizard_state[:require_login],
          allow_edit: @wizard_state[:allow_edit],
          allow_cancel: @wizard_state[:allow_cancel],
          show_registrations: @wizard_state[:show_registrations],
          # Edit cutoff fields
          edit_cutoff_mode: @wizard_state[:edit_cutoff_mode],
          edit_cutoff_days: @wizard_state[:edit_cutoff_days] || 0,
          edit_cutoff_hours: @wizard_state[:edit_cutoff_hours] || 0,
          edit_cutoff_minutes: @wizard_state[:edit_cutoff_minutes] || 0,
          # Cancel cutoff fields
          cancel_cutoff_mode: @wizard_state[:cancel_cutoff_mode],
          cancel_cutoff_days: @wizard_state[:cancel_cutoff_days] || 0,
          cancel_cutoff_hours: @wizard_state[:cancel_cutoff_hours] || 0,
          cancel_cutoff_minutes: @wizard_state[:cancel_cutoff_minutes] || 0,
          # Schedule fields
          schedule_mode: @wizard_state[:schedule_mode],
          opens_days_before: @wizard_state[:opens_days_before] || 7,
          opens_hours_before: @wizard_state[:opens_hours_before] || 0,
          opens_minutes_before: @wizard_state[:opens_minutes_before] || 0,
          closes_mode: @wizard_state[:closes_mode] || "event_start",
          closes_offset_value: calculate_closes_offset_value,
          closes_offset_unit: @wizard_state[:closes_offset_unit] || "hours",
          closes_minutes_offset: @wizard_state[:closes_minutes_offset] || 0,
          holdback_visible: @wizard_state.fetch(:holdback_visible, true),
          notify_on_registration: @wizard_state.fetch(:notify_on_registration, false),
          # Hide registrations fields
          hide_registrations_mode: @wizard_state[:hide_registrations_mode] || "event_start",
          hide_registrations_offset_value: @wizard_state[:hide_registrations_offset_value] || 2,
          hide_registrations_offset_unit: @wizard_state[:hide_registrations_offset_unit] || "hours"
        )

        # Set fixed schedule dates for single_event or fixed mode
        if @wizard_state[:schedule_mode] == "fixed"
          @sign_up_form.opens_at = @wizard_state[:opens_at]
          @sign_up_form.closes_at = @wizard_state[:closes_at]
        end

        # For single_event, set the show_id directly
        if @wizard_state[:scope] == "single_event" && @wizard_state[:selected_show_ids].present?
          @sign_up_form.show_id = @wizard_state[:selected_show_ids].first
        end

        if @sign_up_form.save
          # Create holdback if enabled
          if @wizard_state[:enable_holdbacks] && @wizard_state[:scope] != "shared_pool"
            interval = @wizard_state[:holdback_interval].to_i
            interval = 5 if interval < 2
            label = @wizard_state[:holdback_label].presence || "Hold for walk-ins"
            @sign_up_form.sign_up_form_holdouts.create!(
              holdout_type: "every_n",
              holdout_value: interval,
              reason: label
            )
          end

          # Create sign_up_form_shows for manual selection
          if @wizard_state[:event_matching] == "manual" && @wizard_state[:selected_show_ids].present?
            @wizard_state[:selected_show_ids].each do |show_id|
              @sign_up_form.sign_up_form_shows.create!(show_id: show_id)
            end
          end

          # Generate URL slug
          @sign_up_form.generate_url_slug!

          # Generate short code for /s/:code URLs
          @sign_up_form.generate_short_code!

          # Use SlotManagementService to provision all slots
          slot_service = SlotManagementService.new(@sign_up_form)
          unless slot_service.provision_initial_slots!
            Rails.logger.warn "Slot provisioning had errors: #{slot_service.errors.join(', ')}"
          end

          clear_wizard_state
          redirect_to manage_signups_form_path(@production, @sign_up_form, just_created: true)
        else
          flash.now[:alert] = @sign_up_form.errors.full_messages.to_sentence
          render :review, status: :unprocessable_entity
        end
      end
    end

    # Cancel wizard
    def cancel
      clear_wizard_state
      redirect_to manage_signups_forms_path(@production)
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
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
      "sign_up_wizard:#{Current.user.id}:#{@production.id}"
    end

    def parse_slot_names(names_string)
      return [] if names_string.blank?
      names_string.split(/[\n,]/).map(&:strip).reject(&:blank?)
    end

    def generate_default_name
      case @wizard_state[:scope]
      when "single_event"
        show = @production.shows.find_by(id: @wizard_state[:selected_show_ids].first)
        if show
          if show.secondary_name.present?
            # Use secondary_name directly - it's the most specific
            "#{show.secondary_name} Sign-ups"
          else
            # Fall back to production name + date
            date_str = show.date_and_time.strftime("%b %-d")
            "#{@production.name} Sign-ups (#{date_str})"
          end
        else
          "#{@production.name} Sign-ups"
        end
      when "repeated"
        generate_repeated_name
      else
        "#{@production.name} Waitlist"
      end
    end

    def generate_repeated_name
      case @wizard_state[:event_matching]
      when "event_types"
        event_types = @wizard_state[:event_type_filter]
        if event_types.present? && event_types.any?
          # Use human-readable labels from config
          type_labels = event_types.map { |t| EventTypes.labels[t] || t.titleize }
          if type_labels.size == 1
            label = type_labels.first
            # For generic "Show" type, use production name instead
            if label.downcase == "show"
              "#{@production.name} Sign-ups"
            else
              "#{@production.name} #{label.pluralize} Sign-ups"
            end
          elsif type_labels.size <= 3
            "#{@production.name} Sign-ups"
          else
            "#{@production.name} Sign-ups"
          end
        else
          "#{@production.name} Sign-ups"
        end
      when "manual"
        show_ids = @wizard_state[:selected_show_ids]
        if show_ids.present? && show_ids.any?
          shows = @production.shows.where(id: show_ids).order(:date_and_time)
          if shows.count == 1
            show = shows.first
            # Use secondary_name if present, otherwise production name + date
            if show.secondary_name.present?
              "#{show.secondary_name} Sign-ups"
            else
              date_str = show.date_and_time.strftime("%b %-d")
              "#{@production.name} Sign-ups (#{date_str})"
            end
          else
            # Multiple manual events - check for common secondary_name pattern
            secondary_names = shows.pluck(:secondary_name).compact.reject(&:blank?).uniq
            if secondary_names.size == 1
              # All share the same secondary name
              "#{secondary_names.first} Sign-ups"
            else
              # Use production name with date range
              first_date = shows.first.date_and_time.strftime("%b %-d")
              last_date = shows.last.date_and_time.strftime("%b %-d")
              if first_date == last_date
                "#{@production.name} Sign-ups (#{first_date})"
              else
