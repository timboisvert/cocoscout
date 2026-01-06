# frozen_string_literal: true

module Manage
  class SignUpFormWizardController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :ensure_user_is_manager
    before_action :load_wizard_state

    # Step 1: Scope - What type of sign-up form?
    def scope
      @wizard_state[:scope] ||= "single_event"
    end

    def save_scope
      @wizard_state[:scope] = params[:scope]

      unless %w[single_event per_event shared_pool].include?(@wizard_state[:scope])
        flash.now[:alert] = "Please select a registration scope"
        render :scope, status: :unprocessable_entity and return
      end

      save_wizard_state

      # If single_event or per_event, go to events selection; shared_pool skips to slots
      if @wizard_state[:scope] == "shared_pool"
        redirect_to manage_sign_up_wizard_production_slots_path(@production)
      else
        redirect_to manage_sign_up_wizard_production_events_path(@production)
      end
    end

    # Step 2: Events - Which shows does this form apply to?
    def events
      # Skip this step for shared_pool
      if @wizard_state[:scope] == "shared_pool"
        redirect_to manage_sign_up_wizard_production_slots_path(@production)
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
      redirect_to manage_sign_up_wizard_production_slots_path(@production)
    end

    # Step 3: Slots & Capacity - How are registration slots structured?
    def slots
      @wizard_state[:slot_generation_mode] ||= "numbered"
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
      redirect_to manage_sign_up_wizard_production_rules_path(@production)
    end

    # Step 4: Rules - Registration limits, editing, cancellation
    def rules
      @wizard_state[:registrations_per_person] ||= 1
      @wizard_state[:slot_selection_mode] ||= "choose_slot"
      @wizard_state[:require_login] = true if @wizard_state[:require_login].nil?
      @wizard_state[:allow_edit] = true if @wizard_state[:allow_edit].nil?
      @wizard_state[:allow_cancel] = true if @wizard_state[:allow_cancel].nil?
      @wizard_state[:edit_cutoff_hours] ||= 24
      @wizard_state[:cancel_cutoff_hours] ||= 2
    end

    def save_rules
      @wizard_state[:registrations_per_person] = params[:registrations_per_person].to_i
      @wizard_state[:slot_selection_mode] = params[:slot_selection_mode]
      @wizard_state[:require_login] = params[:require_login] == "1"
      @wizard_state[:allow_edit] = params[:allow_edit] == "1"
      @wizard_state[:allow_cancel] = params[:allow_cancel] == "1"
      @wizard_state[:edit_cutoff_hours] = params[:edit_cutoff_hours].to_i if params[:allow_edit] == "1"
      @wizard_state[:cancel_cutoff_hours] = params[:cancel_cutoff_hours].to_i if params[:allow_cancel] == "1"

      # Holdback settings
      @wizard_state[:enable_holdbacks] = params[:enable_holdbacks] == "1"
      if @wizard_state[:enable_holdbacks]
        @wizard_state[:holdback_interval] = params[:holdback_interval].to_i
        @wizard_state[:holdback_label] = params[:holdback_label]
        @wizard_state[:holdback_visible] = params[:holdback_visible] == "1"
      end

      # Edit/cancel cutoff settings
      @wizard_state[:edit_has_cutoff] = params[:edit_has_cutoff] == "1"
      @wizard_state[:edit_cutoff_mode] = params[:edit_cutoff_mode]
      @wizard_state[:cancel_has_cutoff] = params[:cancel_has_cutoff] == "1"
      @wizard_state[:cancel_cutoff_mode] = params[:cancel_cutoff_mode]

      if @wizard_state[:registrations_per_person] <= 0
        flash.now[:alert] = "Registrations per person must be at least 1"
        render :rules, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_sign_up_wizard_production_schedule_path(@production)
    end

    # Step 5: Schedule - When does registration open/close?
    def schedule
      @wizard_state[:schedule_mode] ||= @wizard_state[:scope] == "single_event" ? "fixed" : "relative"
      @wizard_state[:opens_days_before] ||= 7
      @wizard_state[:closes_hours_before] ||= 2
      @wizard_state[:opens_at] ||= 1.day.from_now.beginning_of_day
      @wizard_state[:closes_at] ||= nil
    end

    def save_schedule
      @wizard_state[:schedule_mode] = params[:schedule_mode]

      if @wizard_state[:schedule_mode] == "relative"
        @wizard_state[:opens_days_before] = params[:opens_days_before].to_i
        @wizard_state[:closes_hours_before] = params[:closes_hours_before].to_i
      else
        @wizard_state[:opens_at] = params[:opens_at]
        @wizard_state[:closes_at] = params[:closes_at].presence
      end

      save_wizard_state
      redirect_to manage_sign_up_wizard_production_review_path(@production)
    end

    # Step 6: Review - Summary of all settings
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
        @sign_up_form = @production.sign_up_forms.new(
          name: params[:name].presence || generate_default_name,
          active: true,
          scope: @wizard_state[:scope],
          event_matching: @wizard_state[:event_matching],
          event_type_filter: @wizard_state[:event_type_filter],
          slot_generation_mode: @wizard_state[:slot_generation_mode],
          slot_count: @wizard_state[:slot_count],
          slot_prefix: @wizard_state[:slot_prefix],
          slot_capacity: @wizard_state[:slot_capacity],
          slot_start_time: @wizard_state[:slot_start_time],
          slot_interval_minutes: @wizard_state[:slot_interval_minutes],
          slot_names: @wizard_state[:slot_names],
          registrations_per_person: @wizard_state[:registrations_per_person],
          slot_selection_mode: @wizard_state[:slot_selection_mode],
          require_login: @wizard_state[:require_login],
          allow_edit: @wizard_state[:allow_edit],
          allow_cancel: @wizard_state[:allow_cancel],
          edit_cutoff_hours: @wizard_state[:edit_cutoff_hours],
          cancel_cutoff_hours: @wizard_state[:cancel_cutoff_hours],
          schedule_mode: @wizard_state[:schedule_mode],
          opens_days_before: @wizard_state[:opens_days_before],
          closes_hours_before: @wizard_state[:closes_hours_before]
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

          # For per_event scope, create instances for matching existing shows
          if @wizard_state[:scope] == "per_event"
            create_instances_for_matching_shows
          elsif @wizard_state[:scope] == "single_event"
            # Create instance for the single show
            create_single_event_instance
          else
            # shared_pool: generate slots directly on the form
            generate_shared_pool_slots
          end

          clear_wizard_state
          redirect_to manage_production_sign_up_form_path(@production, @sign_up_form),
                      notice: "Sign-up form created! You can customize content using Edit Content, or change configuration in Settings."
        else
          flash.now[:alert] = @sign_up_form.errors.full_messages.to_sentence
          render :review, status: :unprocessable_entity
        end
      end
    end

    # Cancel wizard
    def cancel
      clear_wizard_state
      redirect_to manage_production_sign_up_forms_path(@production)
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def load_wizard_state
      session[:sign_up_wizard] ||= {}
      session[:sign_up_wizard][@production.id.to_s] ||= {}
      @wizard_state = session[:sign_up_wizard][@production.id.to_s].with_indifferent_access
    end

    def save_wizard_state
      session[:sign_up_wizard][@production.id.to_s] = @wizard_state.to_h
    end

    def clear_wizard_state
      session[:sign_up_wizard]&.delete(@production.id.to_s)
    end

    def parse_slot_names(names_string)
      return [] if names_string.blank?
      names_string.split(/[\n,]/).map(&:strip).reject(&:blank?)
    end

    def generate_default_name
      case @wizard_state[:scope]
      when "single_event"
        show = @production.shows.find_by(id: @wizard_state[:selected_show_ids].first)
        show_name = show&.secondary_name.presence || show&.event_type&.titleize || "Event"
        "Sign-ups for #{show_name}"
      when "per_event"
        "Event Sign-ups"
      else
        "Sign-up Form"
      end
    end

    def create_instances_for_matching_shows
      shows = case @wizard_state[:event_matching]
      when "all"
        @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current)
      when "event_types"
        @production.shows.where(canceled: false)
                   .where("date_and_time >= ?", Time.current)
                   .where(event_type: @wizard_state[:event_type_filter])
      when "manual"
        @production.shows.where(id: @wizard_state[:selected_show_ids])
      else
        []
      end

      shows.find_each do |show|
        @sign_up_form.create_instance_for_show!(show)
      end
    end

    def create_single_event_instance
      show = @production.shows.find_by(id: @wizard_state[:selected_show_ids].first)
      return unless show

      instance = @sign_up_form.sign_up_form_instances.create!(
        show: show,
        opens_at: @sign_up_form.opens_at,
        closes_at: @sign_up_form.closes_at,
        edit_cutoff_at: @sign_up_form.opens_at,
        status: "scheduled"
      )
      instance.generate_slots_from_template!
    end

    def generate_shared_pool_slots
      case @wizard_state[:slot_generation_mode]
      when "numbered"
        @wizard_state[:slot_count].times do |i|
          @sign_up_form.sign_up_slots.create!(
            position: i + 1,
            name: "#{@wizard_state[:slot_prefix]} #{i + 1}",
            capacity: @wizard_state[:slot_capacity]
          )
        end
      when "time_based"
        start_time = Time.parse(@wizard_state[:slot_start_time])
        @wizard_state[:slot_count].times do |i|
          slot_time = start_time + (i * @wizard_state[:slot_interval_minutes].minutes)
          @sign_up_form.sign_up_slots.create!(
            position: i + 1,
            name: slot_time.strftime("%l:%M %p").strip,
            capacity: @wizard_state[:slot_capacity]
          )
        end
      when "named"
        @wizard_state[:slot_names].each_with_index do |name, i|
          @sign_up_form.sign_up_slots.create!(
            position: i + 1,
            name: name,
            capacity: @wizard_state[:slot_capacity]
          )
        end
      when "simple_capacity"
        @sign_up_form.sign_up_slots.create!(
          position: 1,
          name: nil,
          capacity: @wizard_state[:slot_count]
        )
      end
    end
  end
end
