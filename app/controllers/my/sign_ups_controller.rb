# frozen_string_literal: true

module My
  class SignUpsController < ApplicationController
    allow_unauthenticated_access only: %i[entry form submit_form success inactive]
    before_action :set_sign_up_form, except: [ :index ]

    def index
      @person = Current.user.person
      @people = Current.user.people.active.order(:created_at).to_a

      # Get all groups from all profiles
      @groups = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: @people.map(&:id) })
                     .distinct
                     .order(:name)
                     .to_a

      # Store the filter
      @requests_filter = params[:requests_filter] || session[:requests_filter] || "open"
      session[:requests_filter] = @requests_filter

      # Handle entity filter - comma-separated, now uses person_ID format
      default_entities = @people.map { |p| "person_#{p.id}" } + @groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity] ? params[:entity].split(",") : default_entities

      # Parse selected person IDs and group IDs from entity filter
      selected_person_ids = @people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id)
      selected_group_ids = @groups.select { |g| @entity_filter.include?("group_#{g.id}") }.map(&:id)

      people_by_id = @people.index_by(&:id)
      groups_by_id = @groups.index_by(&:id)

      # ========================================
      # AUDITION REQUESTS (from audition cycles)
      # ========================================
      requestable_conditions = []
      requestable_params = []

      if selected_person_ids.any?
        requestable_conditions << "(requestable_type = 'Person' AND requestable_id IN (?))"
        requestable_params << selected_person_ids
      end

      if selected_group_ids.any?
        requestable_conditions << "(requestable_type = 'Group' AND requestable_id IN (?))"
        requestable_params << selected_group_ids
      end

      @audition_requests = if requestable_conditions.any?
                             AuditionRequest
                               .eager_load(audition_cycle: :production)
                               .where(requestable_conditions.join(" OR "), *requestable_params)
                               .to_a
      else
                             []
      end

      # ========================================
      # SIGN-UP REGISTRATIONS (from sign-up forms)
      # ========================================
      @sign_up_registrations = if selected_person_ids.any?
                                  SignUpRegistration
                                    .eager_load(sign_up_slot: { sign_up_form_instance: :show, sign_up_form: :production })
                                    .where(person_id: selected_person_ids)
                                    .where.not(status: "cancelled")
                                    .to_a
      else
                                  []
      end

      # Apply filter
      case @requests_filter
      when "open"
        # Open audition requests: active, form reviewed, closes_at in future or nil
        @audition_requests = @audition_requests.select do |req|
          req.audition_cycle.active &&
            req.audition_cycle.form_reviewed &&
            (req.audition_cycle.closes_at.nil? || req.audition_cycle.closes_at > Time.current)
        end
        # Open sign-up registrations: form is active and accepting registrations
        @sign_up_registrations = @sign_up_registrations.select do |reg|
          form = reg.sign_up_slot&.sign_up_form
          form&.active? && form&.status_service&.accepting_registrations?
        end
      else
        @requests_filter = "all"
      end

      # Sort audition requests
      @audition_requests = @audition_requests.sort_by do |req|
        req.audition_cycle.closes_at || Time.new(9999)
      end

      # Sort sign-up registrations by show date or form name
      @sign_up_registrations = @sign_up_registrations.sort_by do |reg|
        reg.sign_up_slot&.sign_up_form_instance&.show&.date_and_time || Time.new(9999)
      end

      # Build audition request entities mapping for headshot display
      @audition_request_entities = {}
      @audition_requests.each do |audition_request|
        entities = []

        if audition_request.requestable_type == "Person" && selected_person_ids.include?(audition_request.requestable_id)
          person = people_by_id[audition_request.requestable_id]
          entities << { type: "person", entity: person } if person
        end

        if audition_request.requestable_type == "Group" && selected_group_ids.include?(audition_request.requestable_id)
          group = groups_by_id[audition_request.requestable_id]
          entities << { type: "group", entity: group } if group
        end

        @audition_request_entities[audition_request.id] = entities if entities.any?
      end

      # Build sign-up registration entities mapping
      @sign_up_registration_entities = {}
      @sign_up_registrations.each do |registration|
        if registration.person_id && selected_person_ids.include?(registration.person_id)
          person = people_by_id[registration.person_id]
          @sign_up_registration_entities[registration.id] = [ { type: "person", entity: person } ] if person
        end
      end

      # Build combined list for unified display, sorted by relevance
      @combined_items = []

      # Group sign_up_registrations by sign_up_form to show multiple slots on same row
      registrations_by_form = @sign_up_registrations.group_by { |reg| reg.sign_up_slot&.sign_up_form&.id }
      registrations_by_form.each do |form_id, registrations|
        next unless form_id
        form = registrations.first.sign_up_slot&.sign_up_form
        # Use form.show for single_event, or instance shows for repeated
        sort_date = if form&.scope == "single_event"
          form.show&.date_and_time || Time.new(9999)
        else
          registrations.map { |reg| reg.sign_up_slot&.sign_up_form_instance&.show&.date_and_time }.compact.min || Time.new(9999)
        end
        @combined_items << { type: :sign_up_registrations, records: registrations, sort_date: sort_date }
      end

      @audition_requests.each do |req|
        # Use closes_at for sorting, or far future if open-ended
        sort_date = req.audition_cycle.closes_at || Time.new(9999)
        @combined_items << { type: :audition_request, record: req, sort_date: sort_date }
      end

      # Sort by date (earliest first)
      @combined_items.sort_by! { |item| item[:sort_date] }
    end

    def entry
      # If login is required and user is already signed in, redirect to form
      if authenticated?
        redirect_to my_sign_up_form_path(@code), status: :see_other
        return
      end

      # If login is not required, also redirect to form (guests can sign up)
      unless @sign_up_form.require_login
        redirect_to my_sign_up_form_path(@code), status: :see_other
        return
      end

      unless @sign_up_form.status_service.accepting_registrations?
        redirect_to my_sign_up_inactive_path(@code) and return
      end

      @user = User.new

      # Set the return_to path in case we sign up or sign in
      session[:return_to] = my_sign_up_form_path(@code)
    end

    def form
      # If login is required and user is not signed in, redirect to entry
      if @sign_up_form.require_login && !authenticated?
        redirect_to my_sign_up_entry_path(@code), status: :see_other
        return
      end

      # For repeated events, check if there are multiple open instances
      if @sign_up_form.repeated?
        @open_instances = @sign_up_form.sign_up_form_instances
          .joins(:show)
          .where("shows.date_and_time > ?", Time.current)
          .order("shows.date_and_time ASC")
          .includes(:show)

        # If an instance_id is specified, use that one
        if params[:instance_id].present?
          @instance = @open_instances.find_by(id: params[:instance_id])
        end

        # If no specific instance and multiple are open, user needs to pick
        if @instance.nil? && @open_instances.where(status: "open").count > 1
          @show_event_picker = true
        else
          @instance ||= @open_instances.first
        end
      else
        @instance = find_current_instance
      end

      @slots = @instance&.sign_up_slots&.order(:position) || []
      @questions = @sign_up_form.questions.order(:position)
      @show = @instance&.show
      @my_registrations = find_user_registrations
      @my_registration = @my_registrations.first # For backward compatibility
      @registrations_remaining = registrations_remaining_for_user(@my_registrations)
      @can_register_more = @registrations_remaining > 0
      @can_edit = @sign_up_form.allow_edit && @instance&.can_edit?

      # Allow users to view the form if:
      # 1. Form is accepting registrations, OR
      # 2. User has registrations they can view/edit
      unless @sign_up_form.status_service.accepting_registrations? || @my_registrations.present?
        redirect_to my_sign_up_inactive_path(@code) and return
      end

      # User can always view the form, even if they can't register more
      # The view will show their registration status and hide the form if they can't register more
    end

    def submit_form
      unless @sign_up_form.status_service.accepting_registrations?
        redirect_to my_sign_up_inactive_path(@code) and return
      end

      # Enforce login requirement
      if @sign_up_form.require_login && !authenticated?
        redirect_to my_sign_up_entry_path(@code), status: :see_other
        return
      end

      # For repeated events with instance_id param, find that specific instance
      if @sign_up_form.repeated? && params[:instance_id].present?
        @instance = @sign_up_form.sign_up_form_instances.find_by(id: params[:instance_id])
      end
      @instance ||= find_current_instance

      # Handle admin_assigns mode - user joins the queue, doesn't pick a slot
      if @sign_up_form.admin_assigns?
        submit_to_queue
        return
      end

      slot = @instance.sign_up_slots.find(params[:slot_id])

      # Check if user already has registrations
      existing_registrations = find_user_registrations
      remaining = registrations_remaining_for_user(existing_registrations)

      # If user has no remaining registrations and isn't changing an existing slot
      already_has_this_slot = existing_registrations.any? { |r| r.sign_up_slot_id == slot.id }

      if remaining <= 0 && !already_has_this_slot
        flash[:alert] = "You've reached the maximum number of registrations allowed."
        redirect_to my_sign_up_form_path(@code) and return
      end

      if slot.is_held || (slot.full? && !already_has_this_slot)
        flash[:alert] = "This slot is no longer available."
        redirect_to my_sign_up_form_path(@code) and return
      end

      # If user already has this slot, nothing to do
      if already_has_this_slot
        flash[:notice] = "You're already registered for this slot."
        redirect_to my_sign_up_success_path(@code) and return
      end

      # New registration
      begin
        slot.register!(
          person: Current.user&.person,
          guest_name: params[:guest_name],
          guest_email: params[:guest_email]
        )
        redirect_to my_sign_up_success_path(@code)
      rescue => e
        flash[:alert] = e.message
        redirect_to my_sign_up_form_path(@code)
      end
    end

    def success
      @instance = find_current_instance
      @my_registrations = find_user_registrations
      @my_registration = @my_registrations.first # For backward compatibility
      @my_slot = @my_registration&.sign_up_slot
      @registrations_remaining = registrations_remaining_for_user(@my_registrations)
      @can_register_more = @registrations_remaining > 0
    end

    def change_slot
      @instance = find_current_instance
      @my_registration = find_user_registration

      unless @my_registration
        redirect_to my_sign_up_form_path(@code), alert: "You don't have a registration"
        return
      end

      unless @sign_up_form.allow_edit
        redirect_to my_sign_up_success_path(@code), alert: "Editing is not allowed"
        return
      end

      new_slot = @instance.sign_up_slots.find(params[:slot_id])

      if new_slot.is_held || new_slot.full?
        flash[:alert] = "This slot is no longer available."
        redirect_to my_sign_up_form_path(@code) and return
      end

      # Move registration to new slot
      old_slot = @my_registration.sign_up_slot
      @my_registration.update!(sign_up_slot: new_slot)

      flash[:notice] = "Your slot has been changed"
      redirect_to my_sign_up_success_path(@code)
    rescue => e
      flash[:alert] = e.message
      redirect_to my_sign_up_form_path(@code)
    end

    def cancel_registration
      @instance = find_current_instance
      @my_registrations = find_user_registrations

      unless @my_registrations.any?
        redirect_to my_sign_up_form_path(@code), alert: "You don't have any registrations"
        return
      end

      unless @sign_up_form.allow_cancel
        redirect_to my_sign_up_success_path(@code), alert: "Cancellation is not allowed"
        return
      end

      # Cancel all registrations for this user
      @my_registrations.each do |registration|
        registration.update!(status: "cancelled", cancelled_at: Time.current)
      end

      flash[:notice] = @my_registrations.count == 1 ? "Your registration has been cancelled" : "Your registrations have been cancelled"
      redirect_to my_sign_up_form_path(@code)
    rescue => e
      flash[:alert] = e.message
      redirect_to my_sign_up_success_path(@code)
    end

    def inactive
    end

    private

    def set_sign_up_form
      @code = params[:code]
      @sign_up_form = SignUpForm.find_by!(short_code: @code)
      @production = @sign_up_form.production
    rescue ActiveRecord::RecordNotFound
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end

    def find_current_instance
      case @sign_up_form.scope
      when "single_event"
        @sign_up_form.sign_up_form_instances.first
      when "repeated"
        # Find the first open instance for upcoming events
        @sign_up_form.sign_up_form_instances
          .joins(:show)
          .where(status: "open")
          .where("shows.date_and_time > ?", Time.current)
          .order("shows.date_and_time ASC")
          .first
      when "shared_pool"
        # Shared pool has a single instance with no show
        @sign_up_form.sign_up_form_instances.where(show_id: nil).first
      else
        nil
      end
    end

    def find_user_registrations
      return [] unless @instance
      return [] unless Current.user&.person

      # Find user's active registrations on slots for this instance
      slot_registrations = @instance.sign_up_registrations
        .where(person: Current.user.person)
        .where.not(status: "cancelled")
        .to_a

      # Also find queued registrations for this instance (admin_assigns mode)
      queued_registrations = SignUpRegistration
        .where(sign_up_form_instance_id: @instance.id, person: Current.user.person)
        .where.not(status: "cancelled")
        .to_a

      (slot_registrations + queued_registrations).uniq
    end

    def find_user_registration
      find_user_registrations.first
    end

    def registrations_remaining_for_user(existing_registrations = nil)
      return 0 unless @instance
      return 0 unless Current.user&.person # Guests can only register once

      max_allowed = @sign_up_form.registrations_per_person || 1
      current_count = existing_registrations ? existing_registrations.count : find_user_registrations.count
      [ max_allowed - current_count, 0 ].max
    end

    def submit_to_queue
      # Check if user already has a queued registration for this instance
      if Current.user&.person
        existing = SignUpRegistration.where(
          sign_up_form_instance_id: @instance.id,
          person_id: Current.user.person.id
        ).where.not(status: "cancelled").exists?

        if existing
          flash[:notice] = "You're already in the queue for this event."
          redirect_to my_sign_up_success_path(@code)
          return
        end
      end

      begin
        @instance.register_to_queue!(
          person: Current.user&.person,
          guest_name: params[:guest_name],
          guest_email: params[:guest_email]
        )
        redirect_to my_sign_up_success_path(@code)
      rescue => e
        flash[:alert] = e.message
        redirect_to my_sign_up_form_path(@code)
      end
    end
  end
end
