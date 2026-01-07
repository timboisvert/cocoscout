# frozen_string_literal: true

module Manage
  class SignUpFormsController < Manage::ManageController
    before_action :set_production
    before_action :set_sign_up_form, only: %i[
      show edit update destroy settings update_settings
      confirm_slot_changes apply_slot_changes
      slots create_slot update_slot destroy_slot reorder_slots generate_slots toggle_slot_hold
      holdouts create_holdout destroy_holdout
      questions create_question update_question destroy_question reorder_questions
      registrations register cancel_registration
      preview toggle_active archive unarchive
    ]

    def index
      @sign_up_forms = @production.sign_up_forms.not_archived.order(created_at: :desc)
      @archived_count = @production.sign_up_forms.archived.count
    end

    def archived
      @sign_up_forms = @production.sign_up_forms.archived.order(archived_at: :desc)
    end

    def show
      @slots = @sign_up_form.sign_up_slots.order(:position)
      @registrations = @sign_up_form.sign_up_registrations.includes(:sign_up_slot, :person).active.order("sign_up_slots.position, sign_up_registrations.position")

      # For per-event mode, load instances for event navigation
      if @sign_up_form.per_event?
        @instances = @sign_up_form.sign_up_form_instances
          .joins(:show)
          .includes(:show, :sign_up_slots, sign_up_registrations: [ :sign_up_slot, :person ])
          .where("shows.date_and_time > ?", Time.current)
          .where.not(status: "cancelled")
          .order("shows.date_and_time ASC")

        # Allow selecting a specific instance via params
        if params[:instance_id].present?
          @current_instance = @instances.find_by(id: params[:instance_id])
        end
        @current_instance ||= @instances.first
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
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
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
            redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: tab),
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
      redirect_to manage_production_sign_up_forms_path(@production), notice: "Sign-up form deleted"
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

      success = false

      ActiveRecord::Base.transaction do
        # Handle manual event selection - sync instances
        if params[:selected_show_ids].present? && settings_params[:event_matching] == "manual"
          sync_manual_event_instances(params[:selected_show_ids])
        end

        # Handle holdback settings
        handle_holdback_settings

        # Handle cutoff toggles - set to 0 if disabled
        adjust_cutoff_settings

        if @sign_up_form.update(settings_params)
          success = true
        else
          raise ActiveRecord::Rollback
        end
      end

      if success
        # If slot settings changed and form has existing slots, show confirmation
        if slot_settings_changed && @sign_up_form.sign_up_slots.any?
          # Store pending changes in session for confirmation
          session[:pending_slot_changes] = {
            form_id: @sign_up_form.id,
            old_count: session[:old_slot_count],
            new_count: @sign_up_form.slot_count,
            old_capacity: session[:old_slot_capacity],
            new_capacity: @sign_up_form.slot_capacity
          }
          redirect_to confirm_slot_changes_manage_production_sign_up_form_path(@production, @sign_up_form)
        else
          redirect_to manage_production_sign_up_form_path(@production, @sign_up_form),
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
        redirect_to settings_manage_production_sign_up_form_path(@production, @sign_up_form)
        return
      end

      # For per_event forms, show slots from the first instance as a representative sample
      if @sign_up_form.per_event?
        first_instance = @sign_up_form.sign_up_form_instances.first
        @current_slots = first_instance&.sign_up_slots&.order(:position) || []
      else
        @current_slots = @sign_up_form.sign_up_slots.order(:position)
      end

      @new_slot_count = @sign_up_form.slot_count
      @new_capacity = @sign_up_form.slot_capacity

      # Calculate what new layout would look like
      @preview_slots = build_preview_slots
    end

    def apply_slot_changes
      pending = session.delete(:pending_slot_changes)

      unless pending && pending["form_id"] == @sign_up_form.id
        redirect_to settings_manage_production_sign_up_form_path(@production, @sign_up_form),
                    alert: "No pending changes to apply"
        return
      end

      # Regenerate slots based on new settings using the service
      service = SlotManagementService.new(@sign_up_form)
      service.apply_slot_changes!(preserve_registrations: true)

      redirect_to manage_production_sign_up_form_path(@production, @sign_up_form),
                  notice: "Slot layout updated successfully"
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
      # If edit cutoff toggle is off, ensure hours are 0
      if params[:edit_has_cutoff] == "0" && params[:sign_up_form]
        params[:sign_up_form][:edit_cutoff_hours] = 0
      end

      # If cancel cutoff toggle is off, ensure hours are 0
      if params[:cancel_has_cutoff] == "0" && params[:sign_up_form]
        params[:sign_up_form][:cancel_cutoff_hours] = 0
      end

      # Handle closes_before_after for custom mode - negative means "after"
      if params[:closes_before_after] == "after" && params[:sign_up_form][:closes_offset_value].present?
        params[:sign_up_form][:closes_offset_value] = -params[:sign_up_form][:closes_offset_value].to_i
      end
    end

    def sync_manual_event_instances(show_ids)
      show_ids = Array(show_ids).map(&:to_i)

      # Remove instances for shows no longer selected
      @sign_up_form.sign_up_form_instances.each do |instance|
        instance.destroy unless show_ids.include?(instance.show_id)
      end

      # Add instances for newly selected shows
      existing_show_ids = @sign_up_form.sign_up_form_instances.pluck(:show_id)
      show_ids.each do |show_id|
        unless existing_show_ids.include?(show_id)
          @sign_up_form.sign_up_form_instances.create!(show_id: show_id)
        end
      end
    end

    # Slots management
    def slots
      @slots = @sign_up_form.sign_up_slots.order(:position)
      @holdouts = @sign_up_form.sign_up_form_holdouts
    end

    def create_slot
      next_position = (@sign_up_form.sign_up_slots.maximum(:position) || 0) + 1
      @slot = @sign_up_form.sign_up_slots.new(slot_params.merge(position: next_position))

      if @slot.save
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Slot added successfully"
      else
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
                    alert: @slot.errors.full_messages.join(", ")
      end
    end

    def update_slot
      @slot = @sign_up_form.sign_up_slots.find(params[:slot_id])
      if @slot.update(slot_params)
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Slot updated successfully"
      else
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
                    alert: @slot.errors.full_messages.join(", ")
      end
    end

    def destroy_slot
      @slot = @sign_up_form.sign_up_slots.find(params[:slot_id])
      @slot.destroy
      redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
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
      redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
                  notice: "#{count} slots generated"
    end

    def toggle_slot_hold
      @slot = @sign_up_form.sign_up_slots.find(params[:slot_id])
      if @slot.is_held?
        @slot.release!
      else
        @slot.hold!(reason: params[:reason])
      end
      redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2)
    end

    # Holdouts management
    def holdouts
      @holdouts = @sign_up_form.sign_up_form_holdouts
    end

    def create_holdout
      @holdout = @sign_up_form.sign_up_form_holdouts.new(holdout_params)

      if @holdout.save
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
                    notice: "Holdout rule added"
      else
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
                    alert: @holdout.errors.full_messages.join(", ")
      end
    end

    def destroy_holdout
      @holdout = @sign_up_form.sign_up_form_holdouts.find(params[:holdout_id])
      @holdout.destroy
      redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 2),
                  notice: "Holdout rule removed"
    end

    # Questions management
    def questions
      @questions = @sign_up_form.questions.order(:position)
    end

    def create_question
      next_position = (@sign_up_form.questions.maximum(:position) || 0) + 1
      @question = @sign_up_form.questions.new(question_params.merge(position: next_position))

      if @question.save
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 3),
                    notice: "Question added"
      else
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 3),
                    alert: @question.errors.full_messages.join(", ")
      end
    end

    def update_question
      @question = @sign_up_form.questions.find(params[:question_id])
      if @question.update(question_params)
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 3),
                    notice: "Question updated"
      else
        redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 3),
                    alert: @question.errors.full_messages.join(", ")
      end
    end

    def destroy_question
      @question = @sign_up_form.questions.find(params[:question_id])
      @question.destroy
      redirect_to edit_manage_production_sign_up_form_path(@production, @sign_up_form, tab: 3),
                  notice: "Question deleted"
    end

    def reorder_questions
      ids = params[:ids]
      ids.each_with_index do |id, index|
        @sign_up_form.questions.find(id).update(position: index + 1)
      end
      head :ok
    end

    # Registrations management
    def registrations
      @registrations = @sign_up_form.sign_up_registrations
                                    .includes(:sign_up_slot, :person)
                                    .order("sign_up_slots.position, sign_up_registrations.position")
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
        redirect_to registrations_manage_production_sign_up_form_path(@production, @sign_up_form),
                    notice: "Registration added"
      rescue StandardError => e
        redirect_to registrations_manage_production_sign_up_form_path(@production, @sign_up_form),
                    alert: e.message
      end
    end

    def cancel_registration
      @registration = SignUpRegistration.find(params[:registration_id])
      @registration.cancel!
      redirect_to registrations_manage_production_sign_up_form_path(@production, @sign_up_form),
                  notice: "Registration cancelled"
    end

    def preview
      # For per_event forms, get slots from the first upcoming instance
      # For other forms, get slots directly from the form
      if @sign_up_form.per_event?
        @preview_instance = @sign_up_form.sign_up_form_instances
          .includes(show: :location, sign_up_slots: [])
          .joins(:show)
          .where("shows.date_and_time > ?", Time.current)
          .where.not("shows.canceled = ?", true)
          .order("shows.date_and_time ASC")
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

    def toggle_active
      @sign_up_form.update!(active: !@sign_up_form.active)
      status = @sign_up_form.active? ? "activated" : "deactivated"
      redirect_to manage_production_sign_up_form_path(@production, @sign_up_form),
                  notice: "Sign-up form #{status}"
    end

    def archive
      @sign_up_form.archive!
      redirect_to manage_production_sign_up_forms_path(@production),
                  notice: "Sign-up form archived"
    end

    def unarchive
      @sign_up_form.unarchive!
      redirect_to manage_production_sign_up_form_path(@production, @sign_up_form),
                  notice: "Sign-up form restored"
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
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
        :require_login, :allow_edit, :allow_cancel,
        :edit_cutoff_hours, :cancel_cutoff_hours,
        :enable_holdbacks, :holdback_interval, :holdback_label, :holdback_visible,
        :schedule_mode, :opens_days_before, :closes_hours_before,
        :closes_mode, :closes_offset_value, :closes_offset_unit,
        :opens_at, :closes_at,
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
  end
end
