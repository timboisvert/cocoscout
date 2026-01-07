# frozen_string_literal: true

# SlotManagementService handles all slot lifecycle operations:
# - Creating slots when sign-up forms are created
# - Updating slots when form settings change
# - Creating slots for new shows that match per-event forms
# - Syncing slots across instances when templates change
#
# This is the central authority for slot creation and management.
class SlotManagementService
  class Error < StandardError; end
  class InvalidConfiguration < Error; end

  attr_reader :sign_up_form, :errors

  def initialize(sign_up_form)
    @sign_up_form = sign_up_form
    @errors = []
  end

  # ===========================================
  # PUBLIC API
  # ===========================================

  # Called after a form is created to initialize all slots
  def provision_initial_slots!
    @errors = []

    case sign_up_form.scope
    when "per_event"
      provision_per_event_slots!
    when "single_event"
      provision_single_event_slots!
    when "shared_pool"
      provision_shared_pool_slots!
    end

    errors.empty?
  end

  # Called when form slot settings change
  # Returns a preview of changes without applying them
  def preview_slot_changes
    case sign_up_form.scope
    when "per_event"
      preview_per_event_changes
    when "single_event"
      preview_single_event_changes
    when "shared_pool"
      preview_shared_pool_changes
    end
  end

  # Apply slot changes based on the current form settings
  def apply_slot_changes!(preserve_registrations: true)
    @errors = []

    case sign_up_form.scope
    when "per_event"
      apply_per_event_changes!(preserve_registrations)
    when "single_event"
      apply_single_event_changes!(preserve_registrations)
    when "shared_pool"
      apply_shared_pool_changes!(preserve_registrations)
    end

    errors.empty?
  end

  # Called when a new show is created that might match per-event forms
  # This is typically called from a Show model callback or job
  def self.sync_show_with_forms!(show)
    return unless show.production

    show.production.sign_up_forms.where(scope: "per_event", active: true).find_each do |form|
      next unless form.matches_event?(show)

      service = new(form)
      service.create_instance_for_show!(show)
    end
  end

  # Create an instance for a specific show
  def create_instance_for_show!(show)
    return nil unless sign_up_form.per_event?
    return nil unless sign_up_form.matches_event?(show)

    # Check if instance already exists
    existing = sign_up_form.sign_up_form_instances.find_by(show: show)
    return existing if existing

    instance = sign_up_form.sign_up_form_instances.create!(
      show: show,
      opens_at: calculate_opens_at(show),
      closes_at: calculate_closes_at(show),
      edit_cutoff_at: calculate_edit_cutoff_at(show),
      status: determine_initial_status(show)
    )

    generate_slots_for_instance!(instance)
    instance
  end

  # ===========================================
  # SLOT GENERATION
  # ===========================================

  # Generate slots for an instance based on form template
  def generate_slots_for_instance!(instance)
    return if instance.sign_up_slots.any?

    slots_data = build_slot_template
    return if slots_data.empty?

    ActiveRecord::Base.transaction do
      slots_data.each do |slot_attrs|
        instance.sign_up_slots.create!(slot_attrs.merge(sign_up_form_id: sign_up_form.id))
      end

      apply_holdouts_to_instance!(instance)
    end
  end

  # Generate slots directly on the form (for shared_pool)
  def generate_slots_for_form!
    return if sign_up_form.sign_up_slots.any?

    slots_data = build_slot_template
    return if slots_data.empty?

    ActiveRecord::Base.transaction do
      slots_data.each do |slot_attrs|
        sign_up_form.sign_up_slots.create!(slot_attrs)
      end

      apply_holdouts_to_form!
    end
  end

  # Build the slot template based on form settings
  def build_slot_template
    slots = []

    case sign_up_form.slot_generation_mode
    when "numbered"
      sign_up_form.slot_count.to_i.times do |i|
        slots << {
          position: i + 1,
          name: (i + 1).to_s,
          capacity: sign_up_form.slot_capacity || 1
        }
      end

    when "time_based"
      # Use a default start time if not specified
      start_time_str = sign_up_form.slot_start_time.presence || "7:00 PM"
      interval = sign_up_form.slot_interval_minutes.to_i
      interval = 5 if interval <= 0

      begin
        start_time = Time.parse(start_time_str)
      rescue ArgumentError
        start_time = Time.parse("7:00 PM")
      end

      sign_up_form.slot_count.to_i.times do |i|
        slot_time = start_time + (i * interval.minutes)
        slots << {
          position: i + 1,
          name: slot_time.strftime("%l:%M %p").strip,
          capacity: sign_up_form.slot_capacity || 1
        }
      end

    when "named"
      return [] if sign_up_form.slot_names.blank?

      sign_up_form.slot_names.each_with_index do |name, i|
        slots << {
          position: i + 1,
          name: name,
          capacity: sign_up_form.slot_capacity || 1
        }
      end

    when "simple_capacity", "open_list"
      slots << {
        position: 1,
        name: nil,
        capacity: sign_up_form.slot_count || 10
      }
    end

    slots
  end

  # ===========================================
  # HOLDOUT APPLICATION
  # ===========================================

  def apply_holdouts_to_instance!(instance)
    every_n_holdout = sign_up_form.sign_up_form_holdouts.find_by(holdout_type: "every_n")
    return unless every_n_holdout

    interval = every_n_holdout.holdout_value
    reason = every_n_holdout.reason || "Reserved"

    instance.sign_up_slots.order(:position).each do |slot|
      if (slot.position % interval).zero?
        slot.update!(is_held: true, held_reason: reason)
      end
    end
  end

  def apply_holdouts_to_form!
    every_n_holdout = sign_up_form.sign_up_form_holdouts.find_by(holdout_type: "every_n")
    return unless every_n_holdout

    interval = every_n_holdout.holdout_value
    reason = every_n_holdout.reason || "Reserved"

    sign_up_form.sign_up_slots.order(:position).each do |slot|
      if (slot.position % interval).zero?
        slot.update!(is_held: true, held_reason: reason)
      end
    end
  end

  # ===========================================
  # PRIVATE HELPERS
  # ===========================================

  private

  def provision_per_event_slots!
    sign_up_form.matching_shows.find_each do |show|
      create_instance_for_show!(show)
    rescue StandardError => e
      @errors << "Failed to create instance for show #{show.id}: #{e.message}"
    end
  end

  def provision_single_event_slots!
    instance = sign_up_form.sign_up_form_instances.first
    return unless instance

    generate_slots_for_instance!(instance)
  rescue StandardError => e
    @errors << "Failed to provision single event slots: #{e.message}"
  end

  def provision_shared_pool_slots!
    generate_slots_for_form!
  rescue StandardError => e
    @errors << "Failed to provision shared pool slots: #{e.message}"
  end

  def preview_per_event_changes
    template = build_slot_template
    changes = []

    sign_up_form.sign_up_form_instances.includes(:sign_up_slots).find_each do |instance|
      current_slots = instance.sign_up_slots.order(:position).to_a
      changes << {
        instance: instance,
        show: instance.show,
        current_slots: current_slots,
        new_slots: template,
        slots_to_add: template.size - current_slots.size,
        has_registrations: instance.sign_up_registrations.active.any?
      }
    end

    changes
  end

  def preview_single_event_changes
    instance = sign_up_form.sign_up_form_instances.first
    return [] unless instance

    template = build_slot_template
    current_slots = instance.sign_up_slots.order(:position).to_a

    [ {
      instance: instance,
      show: instance.show,
      current_slots: current_slots,
      new_slots: template,
      slots_to_add: template.size - current_slots.size,
      has_registrations: instance.sign_up_registrations.active.any?
    } ]
  end

  def preview_shared_pool_changes
    template = build_slot_template
    current_slots = sign_up_form.sign_up_slots.order(:position).to_a

    [ {
      current_slots: current_slots,
      new_slots: template,
      slots_to_add: template.size - current_slots.size,
      has_registrations: sign_up_form.sign_up_registrations.active.any?
    } ]
  end

  def apply_per_event_changes!(preserve_registrations)
    sign_up_form.sign_up_form_instances.find_each do |instance|
      sync_instance_slots!(instance, preserve_registrations)
    end
  end

  def apply_single_event_changes!(preserve_registrations)
    instance = sign_up_form.sign_up_form_instances.first
    return unless instance

    sync_instance_slots!(instance, preserve_registrations)
  end

  def apply_shared_pool_changes!(preserve_registrations)
    sync_form_slots!(preserve_registrations)
  end

  def sync_instance_slots!(instance, preserve_registrations)
    template = build_slot_template
    current_slots = instance.sign_up_slots.order(:position).to_a
    new_count = template.size
    current_count = current_slots.size

    ActiveRecord::Base.transaction do
      # Update capacity of existing slots
      current_slots.each_with_index do |slot, i|
        next if i >= new_count
        slot.update!(capacity: template[i][:capacity], name: template[i][:name])
      end

      if new_count > current_count
        # Add new slots
        (current_count...new_count).each do |i|
          instance.sign_up_slots.create!(template[i])
        end
      elsif new_count < current_count && !preserve_registrations
        # Remove excess slots only if no registrations
        slots_to_remove = current_slots[new_count..]
        slots_to_remove.each do |slot|
          slot.destroy if slot.sign_up_registrations.empty?
        end
      end

      apply_holdouts_to_instance!(instance)
    end
  end

  def sync_form_slots!(preserve_registrations)
    template = build_slot_template
    current_slots = sign_up_form.sign_up_slots.order(:position).to_a
    new_count = template.size
    current_count = current_slots.size

    ActiveRecord::Base.transaction do
      # Update capacity of existing slots
      current_slots.each_with_index do |slot, i|
        next if i >= new_count
        slot.update!(capacity: template[i][:capacity], name: template[i][:name])
      end

      if new_count > current_count
        # Add new slots
        (current_count...new_count).each do |i|
          sign_up_form.sign_up_slots.create!(template[i])
        end
      elsif new_count < current_count && !preserve_registrations
        # Remove excess slots only if no registrations
        slots_to_remove = current_slots[new_count..]
        slots_to_remove.each do |slot|
          slot.destroy if slot.sign_up_registrations.empty?
        end
      end

      apply_holdouts_to_form!
    end
  end

  def calculate_opens_at(show)
    return nil unless sign_up_form.schedule_mode == "relative"
    return nil unless sign_up_form.opens_days_before.present?

    show.date_and_time - sign_up_form.opens_days_before.days
  end

  def calculate_closes_at(show)
    case sign_up_form.closes_mode
    when "event_start"
      show.date_and_time
    when "event_end"
      # Assume 2 hour event duration if not specified
      show.date_and_time + 2.hours
    when "custom"
      offset = sign_up_form.closes_offset_value.to_i
      unit = sign_up_form.closes_offset_unit == "days" ? :days : :hours

      if offset >= 0
        show.date_and_time - offset.send(unit)
      else
        show.date_and_time + offset.abs.send(unit)
      end
    else
      # Legacy: use closes_hours_before
      return nil unless sign_up_form.closes_hours_before.present?
      show.date_and_time - sign_up_form.closes_hours_before.hours
    end
  end

  def calculate_edit_cutoff_at(show)
    return nil unless sign_up_form.edit_cutoff_hours.present?
    closes = calculate_closes_at(show) || show.date_and_time
    closes - sign_up_form.edit_cutoff_hours.hours
  end

  def determine_initial_status(show)
    # Always start as initializing - the UpdateSignUpStatusesJob will set the correct status
    "initializing"
  end
end
