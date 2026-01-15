# frozen_string_literal: true

# SlotManagementService handles all slot lifecycle operations:
# - Creating slots when sign-up forms are created
# - Updating slots when form settings change
# - Creating slots for new shows that match repeated forms
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
    when "repeated"
      provision_repeated_slots!
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
    when "repeated"
      preview_repeated_changes
    when "single_event"
      preview_single_event_changes
    when "shared_pool"
      preview_shared_pool_changes
    end
  end

  # Analyze the impact of slot changes on existing registrations
  # Returns a hash with detailed analysis for the confirm page
  def analyze_slot_change_impact
    new_slot_count = build_slot_template.size

    # Get current slots based on scope
    current_slots = case sign_up_form.scope
    when "repeated"
      sign_up_form.sign_up_form_instances.first&.sign_up_slots&.order(:position)&.to_a || []
    when "single_event"
      sign_up_form.sign_up_form_instances.first&.sign_up_slots&.order(:position)&.to_a || []
    when "shared_pool"
      sign_up_form.sign_up_slots.order(:position).to_a
    else
      []
    end

    current_slot_count = current_slots.size

    # Identify slots that would be removed (if reducing count)
    slots_being_removed = new_slot_count < current_slot_count ? current_slots[new_slot_count..] : []

    # Find registrations in slots being removed
    affected_registrations = slots_being_removed.flat_map do |slot|
      slot.sign_up_registrations.active.includes(:person).map do |reg|
        {
          registration: reg,
          slot: slot,
          person: reg.person,
          display_name: reg.display_name
        }
      end
    end

    # Build analysis result
    {
      current_slot_count: current_slot_count,
      new_slot_count: new_slot_count,
      is_increasing: new_slot_count > current_slot_count,
      is_decreasing: new_slot_count < current_slot_count,
      slots_being_added: [ new_slot_count - current_slot_count, 0 ].max,
      slots_being_removed: slots_being_removed,
      affected_registrations: affected_registrations,
      has_affected_registrations: affected_registrations.any?,
      total_current_registrations: current_slots.sum { |s| s.sign_up_registrations.active.count },
      current_slots: current_slots,
      preview_slots: build_slot_template
    }
  end

  # Apply slot changes based on the current form settings
  # affected_registration_action can be:
  #   :reassign - move registrations to available slots (default)
  #   :cancel - cancel the registrations
  def apply_slot_changes!(affected_registration_action: :reassign)
    @errors = []
    @affected_registration_action = affected_registration_action

    case sign_up_form.scope
    when "repeated"
      apply_repeated_changes!
    when "single_event"
      apply_single_event_changes!
    when "shared_pool"
      apply_shared_pool_changes!
    end

    errors.empty?
  end

  # Recalculate opens_at, closes_at, and edit_cutoff_at for all instances
  # Called when schedule settings (opens_days_before, closes_mode, etc.) change
  def recalculate_instance_timings!
    @errors = []

    # First, set all non-cancelled instances to "updating" status
    sign_up_form.sign_up_form_instances.where.not(status: "cancelled").update_all(status: "updating")

    sign_up_form.sign_up_form_instances.where.not(status: "cancelled").find_each do |instance|
      show = instance.show
      next unless show

      instance.update!(
        opens_at: calculate_opens_at(show),
        closes_at: calculate_closes_at(show),
        edit_cutoff_at: calculate_edit_cutoff_at(show)
      )
    end

    # Run status update job immediately to apply new timing
    UpdateSignUpStatusesJob.perform_now

    errors.empty?
  rescue StandardError => e
    @errors << "Failed to recalculate instance timings: #{e.message}"
    false
  end

  # Called when a new show is created that might match repeated forms
  # This is typically called from a Show model callback or job
  def self.sync_show_with_forms!(show)
    return unless show.production

    show.production.sign_up_forms.where(scope: "repeated", active: true).find_each do |form|
      next unless form.matches_event?(show)

      service = new(form)
      service.create_instance_for_show!(show)
    end
  end

  # Create an instance for a specific show
  def create_instance_for_show!(show)
    return nil unless sign_up_form.repeated?
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

    when "simple_capacity"
      # Simple capacity: one slot with capacity = slot_count
      slots << {
        position: 1,
        name: nil,
        capacity: sign_up_form.slot_count || 10
      }

    when "open_list"
      # Open list (waitlist): use single slot with capacity for unlimited/large lists
      # For smaller lists, create individual slots for numbered positions
      slot_count = sign_up_form.slot_count || 10

      if slot_count > 1000
        # For "unlimited" waitlists (999,999), use a single slot with high capacity
        slots << {
          position: 1,
          name: nil,
          capacity: slot_count
        }
      else
        # For smaller lists, create individual slots
        slot_count.times do |i|
          slots << {
            position: i + 1,
            name: nil,
            capacity: 1
          }
        end
      end
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

  def provision_repeated_slots!
    sign_up_form.matching_shows.find_each do |show|
      create_instance_for_show!(show)
    rescue StandardError => e
      @errors << "Failed to create instance for show #{show.id}: #{e.message}"
    end
  end

  def provision_single_event_slots!
    instance = sign_up_form.sign_up_form_instances.first

    # Create instance if it doesn't exist
    unless instance
      show = sign_up_form.show
      return unless show

      instance = sign_up_form.sign_up_form_instances.create!(
        show: show,
        opens_at: calculate_opens_at(show),
        closes_at: calculate_closes_at(show),
        edit_cutoff_at: calculate_edit_cutoff_at(show),
        status: determine_initial_status(show)
      )
    end

    generate_slots_for_instance!(instance)
  rescue StandardError => e
    @errors << "Failed to provision single event slots: #{e.message}"
  end

  def provision_shared_pool_slots!
    # Create a single instance for the shared pool (no show association)
    instance = sign_up_form.sign_up_form_instances.find_or_create_by!(show_id: nil) do |inst|
      inst.status = determine_shared_pool_status
      inst.opens_at = sign_up_form.opens_at
      inst.closes_at = sign_up_form.closes_at
    end

    generate_slots_for_instance!(instance)
  rescue StandardError => e
    @errors << "Failed to provision shared pool slots: #{e.message}"
  end

  def determine_shared_pool_status
    now = Time.current
    if sign_up_form.opens_at.present? && sign_up_form.opens_at > now
      "scheduled"
    else
      "open"
    end
  end

  def preview_repeated_changes
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

  def apply_repeated_changes!
    sign_up_form.sign_up_form_instances.find_each do |instance|
      sync_instance_slots!(instance)
    end
  end

  def apply_single_event_changes!
    instance = sign_up_form.sign_up_form_instances.first
    return unless instance

    sync_instance_slots!(instance)
  end

  def apply_shared_pool_changes!
    sync_form_slots!
  end

  def sync_instance_slots!(instance)
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
          instance.sign_up_slots.create!(template[i].merge(sign_up_form_id: sign_up_form.id))
        end
      elsif new_count < current_count
        # Remove excess slots and handle registrations
        slots_to_remove = current_slots[new_count..]
        remaining_slots = current_slots[0...new_count]

        slots_to_remove.each do |slot|
          active_registrations = slot.sign_up_registrations.active

          if active_registrations.any?
            case @affected_registration_action
            when :reassign
              # Find available slots and reassign registrations
              active_registrations.each do |reg|
                available_slot = remaining_slots.find { |s| !s.full? }
                if available_slot
                  reg.update!(sign_up_slot: available_slot)
                else
                  # No available slot, cancel the registration
                  reg.update!(status: "cancelled")
                end
              end
            when :cancel
              # Cancel all registrations in this slot
              active_registrations.update_all(status: "cancelled")
            end
          end

          slot.destroy
        end
      end

      apply_holdouts_to_instance!(instance)
    end
  end

  def sync_form_slots!
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
      elsif new_count < current_count
        # Remove excess slots and handle registrations
        slots_to_remove = current_slots[new_count..]
        remaining_slots = current_slots[0...new_count]

        slots_to_remove.each do |slot|
          active_registrations = slot.sign_up_registrations.active

          if active_registrations.any?
            case @affected_registration_action
            when :reassign
              # Find available slots and reassign registrations
              active_registrations.each do |reg|
                available_slot = remaining_slots.find { |s| !s.full? }
                if available_slot
                  reg.update!(sign_up_slot: available_slot)
                else
                  # No available slot, cancel the registration
                  reg.update!(status: "cancelled")
                end
              end
            when :cancel
              # Cancel all registrations in this slot
              active_registrations.update_all(status: "cancelled")
            end
          end

          slot.destroy
        end
      end

      apply_holdouts_to_form!
    end
  end

  def calculate_opens_at(show)
    return nil unless sign_up_form.schedule_mode == "relative"

    days = sign_up_form.opens_days_before || 0
    hours = sign_up_form.opens_hours_before || 0
    minutes = sign_up_form.opens_minutes_before || 0

    # If all are zero, no specific opens_at needed (opens immediately when created)
    return nil if days == 0 && hours == 0 && minutes == 0

    show.date_and_time - days.days - hours.hours - minutes.minutes
  end

  def calculate_closes_at(show)
    minutes_offset = (sign_up_form.closes_minutes_offset || 0).minutes

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
        show.date_and_time - offset.send(unit) - minutes_offset
      else
        show.date_and_time + offset.abs.send(unit) + minutes_offset
      end
    else
      # Legacy: use closes_hours_before
      return nil unless sign_up_form.closes_hours_before.present?
      show.date_and_time - sign_up_form.closes_hours_before.hours - minutes_offset
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
