# frozen_string_literal: true

module Manage
  class SignUpFormsController < Manage::ManageController
    before_action :set_production, except: [ :org_index ]
    before_action :set_sign_up_form, only: %i[
      show edit update destroy settings update_settings
      confirm_slot_changes apply_slot_changes
      confirm_event_changes apply_event_changes
      create_slot update_slot destroy_slot reorder_slots generate_slots toggle_slot_hold
      holdouts create_holdout destroy_holdout
      create_question update_question destroy_question reorder_questions
      register register_to_queue cancel_registration move_registration
      preview print_list toggle_active archive unarchive
      assign assign_registration unassign_registration auto_assign_queue auto_assign_one
      transfer
    ]

    # GET /signups/forms (org-wide)
    def org_index
      @filter = params[:filter] # 'registrations' or 'waitlists'

      # Get in-house productions the user has access to (exclude third-party)
      @productions = Current.user.accessible_productions.type_in_house.includes(:sign_up_forms).order(:name)

      # Get all sign-up forms across all productions
      @all_sign_up_forms = SignUpForm.where(production: @productions)
                                      .not_archived
                                      .includes(:production, :sign_up_form_instances, :sign_up_slots)
                                      .order(created_at: :desc)

      # Apply filter if provided
      if @filter == "registrations"
        # Event registrations = single_event or repeated scope (not shared_pool/waitlists)
        @sign_up_forms = @all_sign_up_forms.where(scope: %w[single_event repeated])
        @page_title = "Event Registrations"
        @page_description = "Sign-up forms tied to specific events across all productions."
      elsif @filter == "waitlists"
        # Waitlists = shared_pool scope
        @sign_up_forms = @all_sign_up_forms.where(scope: "shared_pool")
        @page_title = "Waitlists"
        @page_description = "Waitlist forms not tied to specific events across all productions."
      else
        @sign_up_forms = @all_sign_up_forms
        @page_title = "All Sign-up Forms"
        @page_description = "All sign-up forms across all productions."
      end

      # Group by production for display
      @forms_by_production = @sign_up_forms.group_by(&:production)
    end

    # GET /signups/forms/:production_id (production-level)
    def index
      @sign_up_forms = @production.sign_up_forms.not_archived.order(created_at: :desc)

      # Apply filter if provided
      @filter = params[:filter]
      case @filter
      when "registrations"
        # Event registrations = single_event or repeated scope (not shared_pool/waitlists)
        @sign_up_forms = @sign_up_forms.where(scope: %w[single_event repeated])
      when "waitlists"
        # Waitlists = shared_pool scope
        @sign_up_forms = @sign_up_forms.where(scope: "shared_pool")
      end

      @archived_count = @production.sign_up_forms.archived.count
      @wizard_state = Rails.cache.read("sign_up_wizard:#{Current.user.id}:#{@production.id}")
    end

    def archived
      @sign_up_forms = @production.sign_up_forms.archived.order(archived_at: :desc)
    end

    def show
      @slots = @sign_up_form.sign_up_slots.order(:position)
      @registrations = @sign_up_form.sign_up_registrations.includes(:sign_up_slot, :person).active.order("sign_up_slots.position, sign_up_registrations.position")

      # For repeated mode, load instances for event navigation
      if @sign_up_form.repeated?
        # Get all instances that are navigable: open instances OR past closed instances
        # We want to show: past events (read-only) and currently open events
        # Use secondary sort by instance id to ensure deterministic ordering when shows have same date/time
        @instances = @sign_up_form.sign_up_form_instances
          .joins(:show)
          .includes(:show, :sign_up_slots, sign_up_registrations: [ :sign_up_slot, :person ])
          .where.not(status: "cancelled")
          .order("shows.date_and_time ASC, sign_up_form_instances.id ASC")

        # For the right-side list, only show current and upcoming (not past closed)
        @upcoming_instances = @instances.select do |inst|
          inst.show.date_and_time > Time.current || inst.open?
        end

        # Allow selecting a specific instance via params
        if params[:instance_id].present?
          @current_instance = @instances.find_by(id: params[:instance_id])
        end
        # Default to first open instance, or first upcoming, or just first
        @current_instance ||= @instances.find(&:open?) || @upcoming_instances.first || @instances.last
      elsif @sign_up_form.shared_pool?
        # For shared_pool, get the single instance (no show association)
        @current_instance = @sign_up_form.sign_up_form_instances.where(show_id: nil).first
      elsif @sign_up_form.single_event?
        # For single_event, get the single instance
        @current_instance = @sign_up_form.sign_up_form_instances.first
      end
    end

    def new
      @sign_up_form = @production.sign_up_forms.new
      @shows = available_shows
      @question = Question.new
    end

    def create
      @sign_up_form = @production.sign_up_forms.new(sign_up_form_params)

      if @sign_up_form.save
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Sign-up form created successfully. Now configure your slots."
      else
        @shows = available_shows
        @question = Question.new
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @question = Question.new
      @questions = @sign_up_form.questions.order(:position)
    end

    def update
      if @sign_up_form.update(sign_up_form_params)
        respond_to do |format|
          format.html do
            tab = params[:tab].presence || 0
            redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: tab),
                        notice: "Sign-up form updated successfully"
          end
          format.json { render json: { success: true } }
        end
      else
        respond_to do |format|
          format.html do
            @question = Question.new
            @questions = @sign_up_form.questions.order(:position)
            render :edit, status: :unprocessable_entity
          end
          format.json { render json: { success: false, errors: @sign_up_form.errors }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @sign_up_form.destroy
      redirect_to manage_signups_forms_path(@production), notice: "Sign-up form deleted"
    end

    # Settings - Configuration from wizard
    def settings
      @shows = available_shows
      @event_types = EventTypes.for_select
      @slots = @sign_up_form.sign_up_slots.order(:position)
    end

    def update_settings
      # Check if slot-related settings are changing
      slot_settings_changed = slot_settings_will_change?

      # Check if schedule settings are changing
      schedule_settings_changed = schedule_settings_will_change?

      # Check if event associations will change (for repeated forms)
      event_settings_changed = event_settings_will_change?

      success = false

      ActiveRecord::Base.transaction do
        # Handle manual event selection - sync SignUpFormShow records (not instances yet)
        if params[:selected_show_ids].present? && settings_params[:event_matching] == "manual"
          sync_manual_show_selections(params[:selected_show_ids])
        end

        # Handle holdback settings
        handle_holdback_settings

        # Handle cutoff toggles - set to 0 if disabled
        adjust_cutoff_settings

        # Clear opens_at/closes_at when using relative schedule mode
        # (timings are calculated from event dates, not stored on the form)
        clear_fixed_dates_for_relative_mode

        if @sign_up_form.update(settings_params)
          # Recalculate instance timings if schedule settings changed
          if schedule_settings_changed
            SlotManagementService.new(@sign_up_form).recalculate_instance_timings!
          end

          success = true
        else
          raise ActiveRecord::Rollback
        end
      end

      if success
        # Store pending slot changes if needed
        has_existing_slots = case @sign_up_form.scope
        when "shared_pool"
          @sign_up_form.sign_up_slots.any?
        else
          @sign_up_form.sign_up_form_instances.joins(:sign_up_slots).exists?
        end

        if slot_settings_changed && has_existing_slots
          session[:pending_slot_changes] = {
            form_id: @sign_up_form.id,
            old_count: session[:old_slot_count],
            new_count: @sign_up_form.slot_count,
            old_capacity: session[:old_slot_capacity],
            new_capacity: @sign_up_form.slot_capacity
          }
        end

        # Check if event associations need confirmation (for repeated forms)
        if @sign_up_form.repeated? && event_settings_changed
          service = EventAssociationService.new(@sign_up_form)
          event_analysis = service.analyze_event_changes

          if event_analysis[:has_changes]
            # If only adding events (no removals, no affected registrations), apply directly
            if event_analysis[:instances_to_remove_count] == 0 && !event_analysis[:has_affected_registrations]
              result = service.apply_event_changes!
              if result[:success] && result[:created] > 0
                flash[:notice] = "#{result[:created]} event#{'s' if result[:created] > 1} added to sign-up form"
              end
            else
              # Need confirmation for removals
              session[:pending_event_changes] = {
                form_id: @sign_up_form.id
              }
              redirect_to manage_confirm_event_changes_signups_form_path(@production, @sign_up_form)
              return
            end
          end
        end

        # If only slot changes (no event changes), go to slot confirmation
        if session[:pending_slot_changes]&.dig("form_id") == @sign_up_form.id
          redirect_to manage_confirm_slot_changes_signups_form_path(@production, @sign_up_form)
        else
          redirect_to manage_signups_form_path(@production, @sign_up_form),
                      notice: "Settings updated successfully"
        end
      else
        @shows = available_shows
        @event_types = EventTypes.for_select
        @slots = @sign_up_form.sign_up_slots.order(:position)
        render :settings, status: :unprocessable_entity
      end
    end

    def confirm_slot_changes
      @pending_changes = session[:pending_slot_changes]

      unless @pending_changes && @pending_changes["form_id"] == @sign_up_form.id
        redirect_to manage_settings_signups_form_path(@production, @sign_up_form)
        return
      end

      # Use the service to analyze the impact of changes
      service = SlotManagementService.new(@sign_up_form)
      @change_analysis = service.analyze_slot_change_impact

      @current_slots = @change_analysis[:current_slots]
      @preview_slots = @change_analysis[:preview_slots].map { |s| OpenStruct.new(s) }
    end

    def apply_slot_changes
      pending = session.delete(:pending_slot_changes)

      unless pending && pending["form_id"] == @sign_up_form.id
        redirect_to manage_settings_signups_form_path(@production, @sign_up_form),
                    alert: "No pending changes to apply"
        return
      end

      # Handle affected registrations based on user choice
      affected_action = params[:affected_action] || "reassign"

      # Apply slot changes using the service
      service = SlotManagementService.new(@sign_up_form)
      service.apply_slot_changes!(
        affected_registration_action: affected_action.to_sym
      )

      redirect_to manage_signups_form_path(@production, @sign_up_form),
                  notice: "Slot layout updated successfully"
    end

    def confirm_event_changes
      @pending_changes = session[:pending_event_changes]

      unless @pending_changes && @pending_changes["form_id"] == @sign_up_form.id
        redirect_to manage_settings_signups_form_path(@production, @sign_up_form)
        return
      end

      # Use the service to analyze event changes
      service = EventAssociationService.new(@sign_up_form)
      @event_analysis = service.analyze_event_changes
    end

    def apply_event_changes
      pending = session.delete(:pending_event_changes)

      unless pending && pending["form_id"] == @sign_up_form.id
        redirect_to manage_settings_signups_form_path(@production, @sign_up_form),
                    alert: "No pending changes to apply"
        return
      end

      # Handle affected registrations based on user choice
      affected_action = params[:affected_action]&.to_sym || :cancel

      # Apply event changes using the service
      service = EventAssociationService.new(@sign_up_form)
      result = service.apply_event_changes!(affected_registration_action: affected_action)

      if result[:success]
        notice = "Event associations updated"
        notice += " (#{result[:created]} added, #{result[:removed]} removed)" if result[:created] > 0 || result[:removed] > 0

        # Check if there are also pending slot changes to process
        if session[:pending_slot_changes]&.dig("form_id") == @sign_up_form.id
          redirect_to manage_confirm_slot_changes_signups_form_path(@production, @sign_up_form),
                      notice: notice
        else
          redirect_to manage_signups_form_path(@production, @sign_up_form),
                      notice: notice
        end
      else
        redirect_to manage_settings_signups_form_path(@production, @sign_up_form),
                    alert: result[:errors]&.first || "Failed to update event associations"
      end
    end

    def handle_holdback_settings
      if params[:enable_holdbacks] == "1"
        # Create or update the every_n holdout
        interval = params[:holdback_interval].to_i
        interval = 5 if interval < 2
        label = params[:holdback_label].presence || "Hold for walk-ins"

        holdout = @sign_up_form.sign_up_form_holdouts.find_or_initialize_by(holdout_type: "every_n")
        holdout.update!(holdout_value: interval, reason: label)
      else
        # Remove the every_n holdout if it exists
        @sign_up_form.sign_up_form_holdouts.where(holdout_type: "every_n").destroy_all
      end
    end

    def adjust_cutoff_settings
      return unless params[:sign_up_form]

      # If edit cutoff toggle is off, clear the cutoff mode
      if params[:edit_has_cutoff] == "0"
        params[:sign_up_form][:edit_cutoff_mode] = nil
        params[:sign_up_form][:edit_cutoff_days] = 0
        params[:sign_up_form][:edit_cutoff_hours] = 0
        params[:sign_up_form][:edit_cutoff_minutes] = 0
      end

      # If cancel cutoff toggle is off, clear the cutoff mode
      if params[:cancel_has_cutoff] == "0"
        params[:sign_up_form][:cancel_cutoff_mode] = nil
        params[:sign_up_form][:cancel_cutoff_days] = 0
        params[:sign_up_form][:cancel_cutoff_hours] = 0
        params[:sign_up_form][:cancel_cutoff_minutes] = 0
      end

      # Handle closes offset calculation from days/hours fields
      # Use key? instead of present? because 0.present? returns false
      if params.key?(:closes_offset_days) || params.key?(:closes_offset_hours)
        total_hours = (params[:closes_offset_days].to_i * 24) + params[:closes_offset_hours].to_i
        # If "after" the event, store as negative value
        if params[:closes_before_after] == "after"
          params[:sign_up_form][:closes_offset_value] = -total_hours
        else
          params[:sign_up_form][:closes_offset_value] = total_hours
        end
        params[:sign_up_form][:closes_offset_unit] = "hours"
        # Also save closes_hours_before for backward compatibility
        params[:sign_up_form][:closes_hours_before] = total_hours.abs
      end
    end

    def create_slot
      next_position = (@sign_up_form.sign_up_slots.maximum(:position) || 0) + 1
      @slot = @sign_up_form.sign_up_slots.new(slot_params.merge(position: next_position))

      if @slot.save
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Slot added successfully"
      else
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    alert: @slot.errors.full_messages.join(", ")
      end
    end

    def update_slot
      @slot = @sign_up_form.sign_up_slots.find(params[:slot_id])
      if @slot.update(slot_params)
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Slot updated successfully"
      else
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    alert: @slot.errors.full_messages.join(", ")
      end
    end

    def destroy_slot
      @slot = @sign_up_form.sign_up_slots.find(params[:slot_id])
      @slot.destroy
      redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                  notice: "Slot deleted"
    end

    def reorder_slots
      ids = params[:ids]
      ids.each_with_index do |id, index|
        @sign_up_form.sign_up_slots.find(id).update(position: index + 1)
      end
      @sign_up_form.apply_holdouts!
      head :ok
    end

    def generate_slots
      count = params[:count].to_i
      count = 10 if count <= 0 || count > 100
      prefix = params[:prefix].presence || "Slot"

      starting_position = (@sign_up_form.sign_up_slots.maximum(:position) || 0) + 1

      count.times do |i|
        @sign_up_form.sign_up_slots.create!(
          position: starting_position + i,
          name: "#{prefix} #{starting_position + i}",
          capacity: (params[:capacity].presence || 1).to_i
        )
      end

      @sign_up_form.apply_holdouts!
      redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                  notice: "#{count} slots generated"
    end

    def toggle_slot_hold
      @slot = @sign_up_form.sign_up_slots.find(params[:slot_id])
      if @slot.is_held?
        @slot.release!
      else
        @slot.hold!(reason: params[:reason])
      end
      redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2)
    end

    # Holdouts management
    def holdouts
      @holdouts = @sign_up_form.sign_up_form_holdouts
    end

    def create_holdout
      @holdout = @sign_up_form.sign_up_form_holdouts.new(holdout_params)

      if @holdout.save
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Holdout rule added"
      else
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    alert: @holdout.errors.full_messages.join(", ")
      end
    end

    def destroy_holdout
      @holdout = @sign_up_form.sign_up_form_holdouts.find(params[:holdout_id])
      @holdout.destroy
      redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                  notice: "Holdout rule removed"
    end

    def create_question
      next_position = (@sign_up_form.questions.maximum(:position) || 0) + 1
      @question = @sign_up_form.questions.new(question_params.merge(position: next_position))

      if @question.save
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Question added"
      else
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    alert: @question.errors.full_messages.join(", ")
      end
    end

    def update_question
      @question = @sign_up_form.questions.find(params[:question_id])
      if @question.update(question_params)
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Question updated"
      else
        redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                    alert: @question.errors.full_messages.join(", ")
      end
    end

    def destroy_question
      @question = @sign_up_form.questions.find(params[:question_id])
      @question.destroy
      redirect_to manage_edit_signups_form_path(@production, @sign_up_form, tab: 2),
                  notice: "Question deleted"
    end

    def reorder_questions
      ids = params[:ids]
      ids.each_with_index do |id, index|
        @sign_up_form.questions.find(id).update(position: index + 1)
      end
      head :ok
    end

    def register
      @slot = @sign_up_form.sign_up_slots.find(params[:slot_id])

      person = if params[:person_id].present?
        Person.find(params[:person_id])
      end

      begin
        @registration = @slot.register!(
          person: person,
          guest_name: params[:guest_name],
          guest_email: params[:guest_email]
        )
        redirect_to manage_signups_form_path(@production, @sign_up_form),
                    notice: "Registration added"
      rescue StandardError => e
        redirect_to manage_signups_form_path(@production, @sign_up_form),
                    alert: e.message
      end
    end

    def register_to_queue
      instance_id = params[:instance_id]
      @instance = @sign_up_form.sign_up_form_instances.find(instance_id)

      person = if params[:person_id].present?
        Person.find(params[:person_id])
      end

      begin
        @registration = @instance.register_to_queue!(
          person: person,
          guest_name: params[:guest_name],
          guest_email: params[:guest_email]
        )
        redirect_to manage_signups_form_path(@production, @sign_up_form, instance_id: @instance.id),
                    notice: "Added to queue"
      rescue StandardError => e
        redirect_to manage_signups_form_path(@production, @sign_up_form, instance_id: @instance.id),
                    alert: e.message
      end
    end

    def cancel_registration
      @registration = SignUpRegistration.find(params[:registration_id])
      @registration.cancel!
      redirect_to manage_signups_form_path(@production, @sign_up_form),
                  notice: "Registration cancelled"
    end

    def move_registration
      @registration = SignUpRegistration.find(params[:registration_id])
      target_slot = SignUpSlot.find(params[:target_slot_id])

      # Ensure the target slot belongs to the same form
      unless target_slot.sign_up_form_id == @sign_up_form.id ||
             target_slot.sign_up_form_instance&.sign_up_form_id == @sign_up_form.id
        redirect_to manage_signups_form_path(@production, @sign_up_form),
                    alert: "Invalid target slot"
        return
      end

      # Check if slot has available capacity
      unless target_slot.spots_remaining > 0
        redirect_to manage_signups_form_path(@production, @sign_up_form),
                    alert: "Target slot is full"
        return
      end

      # Move the registration
      old_slot = @registration.sign_up_slot
      @registration.update!(
        sign_up_slot: target_slot,
        position: target_slot.sign_up_registrations.active.count + 1
      )

      redirect_to manage_signups_form_path(@production, @sign_up_form),
                  notice: "Moved #{@registration.display_name} to #{target_slot.name.presence || "slot #{target_slot.position}"}"
    end

    def preview
      # For repeated forms, get slots from the first upcoming instance
      # For other forms, get slots directly from the form
      if @sign_up_form.repeated?
        @preview_instance = @sign_up_form.sign_up_form_instances
          .includes(show: :location, sign_up_slots: [])
          .joins(:show)
          .where("shows.date_and_time > ?", Time.current)
          .where.not("shows.canceled = ?", true)
          .order("shows.date_and_time ASC, sign_up_form_instances.id ASC")
          .first
        @slots = @preview_instance&.sign_up_slots&.order(:position) || []
        @preview_show = @preview_instance&.show
      elsif @sign_up_form.single_event?
        @preview_show = @sign_up_form.show
        @preview_show = Show.includes(:location).find(@preview_show.id) if @preview_show
        @slots = @sign_up_form.sign_up_slots.order(:position)
      else
        @preview_show = nil
        @slots = @sign_up_form.sign_up_slots.order(:position)
      end
      @questions = @sign_up_form.questions.order(:position)
    end

    def print_list
      # Load instance based on params or default to first open/upcoming
      if @sign_up_form.repeated?
        @instances = @sign_up_form.sign_up_form_instances
          .joins(:show)
          .includes(:show, sign_up_slots: { sign_up_registrations: :person })
          .where.not(status: "cancelled")
          .order("shows.date_and_time ASC, sign_up_form_instances.id ASC")

        if params[:instance_id].present?
          @current_instance = @instances.find_by(id: params[:instance_id])
        end
        @current_instance ||= @instances.find(&:open?) || @instances.select { |i| i.show.date_and_time > Time.current }.first || @instances.last
        @slots = @current_instance&.sign_up_slots&.order(:position) || []
        @show = @current_instance&.show
      elsif @sign_up_form.single_event?
        @current_instance = @sign_up_form.sign_up_form_instances.includes(sign_up_slots: { sign_up_registrations: :person }).first
        @slots = @current_instance&.sign_up_slots&.order(:position) || @sign_up_form.sign_up_slots.order(:position)
        @show = @sign_up_form.show
      else
        @current_instance = @sign_up_form.sign_up_form_instances.includes(sign_up_slots: { sign_up_registrations: :person }).first
        @slots = @current_instance&.sign_up_slots&.order(:position) || @sign_up_form.sign_up_slots.order(:position)
        @show = nil
      end

      render layout: "print"
    end

    def toggle_active
      @sign_up_form.update!(active: !@sign_up_form.active)
      status = @sign_up_form.active? ? "activated" : "deactivated"
      redirect_to manage_signups_form_path(@production, @sign_up_form),
                  notice: "Sign-up form #{status}"
    end

    def archive
      @sign_up_form.archive!
      redirect_to manage_signups_forms_path(@production),
                  notice: "Sign-up form archived"
    end

    def unarchive
      @sign_up_form.unarchive!
      redirect_to manage_signups_form_path(@production, @sign_up_form),
                  notice: "Sign-up form restored"
    end

    def transfer
      target_production_id = params[:target_production_id]
      target_production = Current.user.accessible_productions.find_by(id: target_production_id)

      unless target_production
        redirect_to manage_signups_form_path(@production, @sign_up_form),
                    alert: "Target production not found or you don't have access"
        return
      end

      if target_production.id == @production.id
        redirect_to manage_signups_form_path(@production, @sign_up_form),
                    alert: "Cannot move to the same production"
        return
      end

      # Perform the transfer
      SignUpFormTransferService.transfer(@sign_up_form, target_production)

      # Switch to the target production in the session
      session[:current_production_id_for_organization] ||= {}
      session[:current_production_id_for_organization]["#{Current.user.id}_#{Current.organization.id}"] = target_production.id

      redirect_to manage_signups_form_path(target_production, @sign_up_form),
                  notice: "Sign-up form moved to #{target_production.name}"
    rescue StandardError => e
      redirect_to manage_signups_form_path(@production, @sign_up_form),
                  alert: "Failed to move sign-up form: #{e.message}"
    end

    # Queue assignment UI for admin_assigns mode
    def assign
      unless @sign_up_form.admin_assigns?
        redirect_to manage_signups_form_path(@production, @sign_up_form),
                    alert: "Assignment is only available for forms with 'Production team assigns registrants to slots' mode"
        return
      end

      load_assignment_data
    end

    def assign_registration
      registration = SignUpRegistration.find(params[:registration_id])
      slot = @sign_up_form.sign_up_slots.find(params[:slot_id])

      if slot.full?
        redirect_to manage_assign_signups_form_path(@production, @sign_up_form, instance_id: params[:instance_id]),
                    alert: "Slot is full"
        return
      end

      registration.assign_to_slot!(slot)
      redirect_to manage_assign_signups_form_path(@production, @sign_up_form, instance_id: params[:instance_id]),
                  notice: "#{registration.display_name} assigned to #{slot.display_name}"
    end

    def unassign_registration
      registration = SignUpRegistration.find(params[:registration_id])
      registration.unassign!
      redirect_to manage_assign_signups_form_path(@production, @sign_up_form, instance_id: params[:instance_id]),
                  notice: "#{registration.display_name} returned to queue"
    end

    def auto_assign_queue
      @instance = find_instance_for_assignment
      return unless @instance

      assigned_count = 0
      @instance.queued_registrations.each do |registration|
        # Find first available slot
        slot = @instance.sign_up_slots.available.find { |s| !s.full? }
        break unless slot

        registration.assign_to_slot!(slot)
        assigned_count += 1
      end

      redirect_to manage_assign_signups_form_path(@production, @sign_up_form, instance_id: @instance.id),
                  notice: "Auto-assigned #{assigned_count} people to slots"
    end

    def auto_assign_one
      @instance = find_instance_for_assignment
      return unless @instance

      registration = SignUpRegistration.find(params[:registration_id])

      # Find first available slot
      slot = @instance.sign_up_slots.available.find { |s| !s.full? }
      if slot
        registration.assign_to_slot!(slot)
        redirect_to manage_assign_signups_form_path(@production, @sign_up_form, instance_id: @instance.id),
                    notice: "#{registration.display_name} assigned to #{slot.display_name}"
      else
        redirect_to manage_assign_signups_form_path(@production, @sign_up_form, instance_id: @instance.id),
                    alert: "No available slots"
      end
    end

    private

    def load_assignment_data
      @instance = find_instance_for_assignment
      return unless @instance

      @slots = @instance.sign_up_slots.order(:position).includes(:sign_up_registrations)
      @queue = @instance.queued_registrations.includes(:person)
      @assigned = @instance.sign_up_registrations.active.assigned.includes(:person, :sign_up_slot)
    end

    def find_instance_for_assignment
      if params[:instance_id].present?
        @sign_up_form.sign_up_form_instances.find_by(id: params[:instance_id])
      elsif @sign_up_form.repeated?
        @sign_up_form.sign_up_form_instances.joins(:show)
          .where("shows.date_and_time > ?", Time.current)
          .order("shows.date_and_time ASC, sign_up_form_instances.id ASC").first
      else
        @sign_up_form.sign_up_form_instances.first
      end
    end

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def set_sign_up_form
      @sign_up_form = @production.sign_up_forms.find(params[:id])
    end

    def sign_up_form_params
      params.require(:sign_up_form).permit(
        :name, :description, :show_id, :active, :require_login,
        :opens_at, :closes_at, :slots_per_registration,
        :instruction_text, :success_text
      )
    end

    def settings_params
      params.require(:sign_up_form).permit(
        :name,
        :scope, :event_matching, :show_id,
        :slot_generation_mode, :slot_count, :slot_prefix, :slot_capacity,
        :slot_start_time, :slot_interval_minutes, :slot_names,
        :registrations_per_person, :slot_selection_mode,
        :require_login, :show_registrations, :allow_edit, :allow_cancel,
        :edit_cutoff_hours, :cancel_cutoff_hours,
        :edit_cutoff_mode, :edit_cutoff_days, :edit_cutoff_minutes,
        :cancel_cutoff_mode, :cancel_cutoff_days, :cancel_cutoff_minutes,
        :enable_holdbacks, :holdback_interval, :holdback_label, :holdback_visible,
        :schedule_mode, :opens_days_before, :opens_hours_before, :opens_minutes_before,
        :closes_hours_before, :closes_minutes_offset,
        :closes_mode, :closes_offset_value, :closes_offset_unit,
        :opens_at, :closes_at,
        :notify_on_registration,
        :queue_limit, :queue_carryover,
        :slot_hold_enabled, :slot_hold_seconds,
        :hide_registrations_mode, :hide_registrations_offset_value, :hide_registrations_offset_unit,
        event_type_filter: []
      )
    end

    def slot_params
      params.require(:slot).permit(:name, :capacity, :is_held, :held_reason)
    end

    def holdout_params
      params.require(:holdout).permit(:holdout_type, :holdout_value, :reason)
    end

    def question_params
      params.require(:question).permit(
        :text, :question_type, :required,
        question_options_attributes: %i[id text position _destroy]
      )
    end

    def available_shows
      @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
    end

    def slot_settings_will_change?
      # Store current values before update
      session[:old_slot_count] = @sign_up_form.slot_count
      session[:old_slot_capacity] = @sign_up_form.slot_capacity

      new_count = settings_params[:slot_count]&.to_i
      new_capacity = settings_params[:slot_capacity]&.to_i

      return false if new_count.nil? && new_capacity.nil?

      (new_count.present? && new_count != @sign_up_form.slot_count) ||
        (new_capacity.present? && new_capacity != @sign_up_form.slot_capacity)
    end

    def schedule_settings_will_change?
      new_schedule_mode = settings_params[:schedule_mode]
      new_opens_days_before = settings_params[:opens_days_before]&.to_i
      new_closes_mode = settings_params[:closes_mode]
      new_closes_offset_value = settings_params[:closes_offset_value]&.to_i
      new_closes_offset_unit = settings_params[:closes_offset_unit]

      (new_schedule_mode.present? && new_schedule_mode != @sign_up_form.schedule_mode) ||
        (new_opens_days_before.present? && new_opens_days_before != @sign_up_form.opens_days_before) ||
        (new_closes_mode.present? && new_closes_mode != @sign_up_form.closes_mode) ||
        (new_closes_offset_value.present? && new_closes_offset_value != @sign_up_form.closes_offset_value) ||
        (new_closes_offset_unit.present? && new_closes_offset_unit != @sign_up_form.closes_offset_unit)
    end

    def clear_fixed_dates_for_relative_mode
      # When using relative schedule mode, clear any fixed dates
      # Instance timings are calculated from event dates, not stored on the form
      if settings_params[:schedule_mode] == "relative"
        @sign_up_form.opens_at = nil
        @sign_up_form.closes_at = nil
      end
    end

    def build_preview_slots
      # Build what the new slot layout would look like
      preview = []
      case @sign_up_form.slot_generation_mode
      when "numbered"
        @sign_up_form.slot_count.times do |i|
          preview << OpenStruct.new(
            position: i + 1,
            name: (i + 1).to_s,
            capacity: @sign_up_form.slot_capacity,
            is_held: should_slot_be_held?(i + 1)
          )
        end
      when "time_based"
        start_time = Time.parse(@sign_up_form.slot_start_time) rescue Time.current
        @sign_up_form.slot_count.times do |i|
          slot_time = start_time + (i * @sign_up_form.slot_interval_minutes.to_i.minutes)
          preview << OpenStruct.new(
            position: i + 1,
            name: slot_time.strftime("%l:%M %p").strip,
            capacity: @sign_up_form.slot_capacity,
            is_held: should_slot_be_held?(i + 1)
          )
        end
      end
      preview
    end

    def should_slot_be_held?(position)
      holdout = @sign_up_form.sign_up_form_holdouts.find_by(holdout_type: "every_n")
      return false unless holdout

      (position % holdout.holdout_value).zero?
    end

    def event_settings_will_change?
      return false unless @sign_up_form.repeated?

      # Store current state for comparison
      current_show_ids = @sign_up_form.sign_up_form_instances.pluck(:show_id).to_set

      new_event_matching = settings_params[:event_matching]
      new_event_type_filter = settings_params[:event_type_filter]

      # If event_matching is changing, events will likely change
      if new_event_matching.present? && new_event_matching != @sign_up_form.event_matching
        return true
      end

      # If event_type_filter is changing (and mode is event_types), events will change
      if @sign_up_form.event_matching == "event_types" || new_event_matching == "event_types"
        if new_event_type_filter.present?
          current_filter = @sign_up_form.event_type_filter || []
          new_filter = Array(new_event_type_filter).reject(&:blank?)
          return true if current_filter.sort != new_filter.sort
        end
      end

      # For manual mode, check if selected shows are different
      if new_event_matching == "manual" && params[:selected_show_ids].present?
        selected_ids = Array(params[:selected_show_ids]).map(&:to_i).to_set
        current_selected_ids = @sign_up_form.sign_up_form_shows.pluck(:show_id).to_set
        return true if selected_ids != current_selected_ids
      end

      # Check if there are no instances but there should be (needs sync)
      if current_show_ids.empty?
        # Calculate what would match
        matching_count = @sign_up_form.matching_shows.count
        return true if matching_count > 0
      end

      false
    end

    def sync_manual_show_selections(show_ids)
      # Sync SignUpFormShow records (the selection), not instances
      # Instances are created/removed during apply_event_changes
      show_ids = Array(show_ids).map(&:to_i).reject(&:zero?)

      # Remove selections no longer selected
      @sign_up_form.sign_up_form_shows.where.not(show_id: show_ids).destroy_all

      # Add newly selected shows
      existing_show_ids = @sign_up_form.sign_up_form_shows.pluck(:show_id)
      show_ids.each do |show_id|
        unless existing_show_ids.include?(show_id)
          @sign_up_form.sign_up_form_shows.create!(show_id: show_id)
        end
      end
    end
  end
end
