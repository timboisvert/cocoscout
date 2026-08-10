# frozen_string_literal: true

module My
  class SignUpsController < ApplicationController
    allow_unauthenticated_access only: %i[entry form submit_form success inactive lock_slot unlock_slot slot_locks]
    before_action :set_sign_up_form

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
      # Prevent browser from caching this page (back button issue)
      response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
      response.headers["Pragma"] = "no-cache"
      response.headers["Expires"] = "0"

      # If login is required and user is not signed in, redirect to entry
      if @sign_up_form.require_login && !authenticated?
        redirect_to my_sign_up_entry_path(@code), status: :see_other
        return
      end

      # For repeated events, check if there are multiple open instances
      if @sign_up_form.repeated?
        @open_instances = @sign_up_form.sign_up_form_instances
          .joins(:show)
          .where(status: "open")
          .where("shows.date_and_time > ?", Time.current)
          .order("shows.date_and_time ASC, sign_up_form_instances.id ASC")
          .includes(:show)

        # If an instance_id is specified, use that one
        if params[:instance_id].present?
          # First try to find in open instances
          @instance = @open_instances.find_by(id: params[:instance_id])
          # If not found but show_registrations is enabled, allow viewing past events
          if @instance.nil? && @sign_up_form.show_registrations
            @instance = @sign_up_form.sign_up_form_instances
              .includes(:show)
              .find_by(id: params[:instance_id])
          end
        end

        # If no specific instance and multiple are open, user needs to pick
        if @instance.nil? && @open_instances.count > 1
          @show_event_picker = true
        elsif @instance.nil?
          @instance = @open_instances.first
          # If no open instances but show_registrations is enabled, show the most recent past event
          # (not future events that haven't opened yet)
          if @instance.nil? && @sign_up_form.show_registrations
            @instance = @sign_up_form.sign_up_form_instances
              .joins(:show)
              .where("shows.date_and_time < ?", Time.current)
              .order("shows.date_and_time DESC")
              .includes(:show)
              .first
          end
        end
      else
        @instance = find_current_instance
      end

      @slots = @instance&.sign_up_slots&.includes(:sign_up_registrations)&.order(:position) || []
      @questions = @sign_up_form.questions.order(:position)
      @show = @instance&.show
      @my_registrations = find_user_registrations
      @my_registration = @my_registrations.first # For backward compatibility
      @registrations_remaining = registrations_remaining_for_user(@my_registrations)
      @can_register_more = @registrations_remaining > 0
      @can_edit = @sign_up_form.allow_edit && @instance&.can_edit?
      @is_accepting_registrations = @sign_up_form.status_service.accepting_registrations?
      @registrations_visible = @sign_up_form.registrations_visible_for_show?(@show)

      # Allow users to view the form if:
      # 1. Form is accepting registrations, OR
      # 2. User has registrations they can view/edit, OR
      # 3. Form has show_registrations enabled AND registrations are still visible
      unless @is_accepting_registrations || @my_registrations.present? || @registrations_visible
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
        registration = slot.register!(
          person: Current.user&.person,
          guest_name: params[:guest_name],
          guest_email: params[:guest_email]
        )

        # Send confirmation email to registrant
        SignUpRegistrantNotificationJob.perform_later(registration.id, :confirmation)

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

      # Don't allow slot changes if the form is paused or registration is closed
      unless @sign_up_form.status_service.accepting_registrations?
        redirect_to my_sign_up_success_path(@code), alert: "Registration is not currently open"
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

      # Send slot changed email to registrant
      SignUpRegistrantNotificationJob.perform_later(@my_registration.id, :slot_changed)

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
        # Send cancellation email to registrant
        SignUpRegistrantNotificationJob.perform_later(registration.id, :cancelled)
      end

      flash[:notice] = @my_registrations.count == 1 ? "Your registration has been cancelled" : "Your registrations have been cancelled"
      redirect_to my_sign_up_form_path(@code)
    rescue => e
      flash[:alert] = e.message
      redirect_to my_sign_up_success_path(@code)
    end

    def inactive
      # If the form is active and accepting registrations, redirect to the form
      form_status = @sign_up_form.current_status
      if form_status[:accepting_registrations]
        redirect_to my_sign_up_form_path(@code) and return
      end
    end

    # Lock a slot while user completes registration
    def lock_slot
      slot = @sign_up_form.sign_up_slots.find(params[:slot_id])

      # Check if slot is actually available
      if slot.is_held || slot.full?
        render json: { success: false, error: "Slot is not available" }, status: :unprocessable_entity
        return
      end

      # Use the form's configured hold duration
      duration = @sign_up_form.slot_hold_seconds || 30
      result = SlotLockService.acquire(slot.id, session_identifier, duration: duration)

      if result[:success]
        render json: { success: true, expires_in: result[:expires_in], slot_id: slot.id }
      else
        render json: { success: false, error: result[:error], expires_in: result[:expires_in] }, status: :conflict
      end
    end

    # Release a slot lock (user cancelled or navigated away)
    def unlock_slot
      slot = @sign_up_form.sign_up_slots.find(params[:slot_id])

      SlotLockService.release(slot.id, session_identifier)
      render json: { success: true }
    end

    # Get lock status for all slots in an instance (for UI updates)
    def slot_locks
      @instance = if params[:instance_id].present?
        @sign_up_form.sign_up_form_instances.find_by(id: params[:instance_id])
      else
        find_current_instance
      end

      unless @instance
        render json: { locks: {} }
        return
      end

      slot_ids = @instance.sign_up_slots.pluck(:id)
      locks = SlotLockService.bulk_lock_info(slot_ids, session_identifier)
      render json: { locks: locks }
    end

    private

    def session_identifier
      # Use session ID for guests, user ID for logged-in users
      Current.user&.id&.to_s || session.id.to_s
    end

    def set_sign_up_form
      @code = params[:code]
      @sign_up_form = SignUpForm.find_by!(short_code: @code)
      @production = @sign_up_form.production
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
          .order("shows.date_and_time ASC, sign_up_form_instances.id ASC")
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
        registration = @instance.register_to_queue!(
          person: Current.user&.person,
          guest_name: params[:guest_name],
          guest_email: params[:guest_email]
        )

        # Send queued email to registrant
        SignUpRegistrantNotificationJob.perform_later(registration.id, :queued)

        redirect_to my_sign_up_success_path(@code)
      rescue => e
        flash[:alert] = e.message
        redirect_to my_sign_up_form_path(@code)
      end
    end
  end
end
