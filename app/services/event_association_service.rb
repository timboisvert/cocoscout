# frozen_string_literal: true

# EventAssociationService manages sign-up form to event associations
# for "repeated" scope forms. It handles:
# - Analyzing what events currently match vs what would match
# - Creating/removing SignUpFormInstance records
# - Preserving registrations when possible
#
# This service is used when:
# - Updating sign-up form settings (event_matching, event_type_filter)
# - After moving a sign-up form to a different production
# - Manually triggering a sync
class EventAssociationService
  class Error < StandardError; end

  attr_reader :sign_up_form, :errors

  def initialize(sign_up_form)
    @sign_up_form = sign_up_form
    @errors = []
  end

  # Analyze what would change if we synced events now
  # Returns a hash with detailed analysis for the confirm page
  def analyze_event_changes
    return empty_analysis unless sign_up_form.repeated?

    current_instances = sign_up_form.sign_up_form_instances
                                     .includes(show: :location, sign_up_slots: :sign_up_registrations)
                                     .where.not(show_id: nil)
                                     .to_a
    current_show_ids = current_instances.map(&:show_id).to_set

    # Get shows that would match based on current settings
    new_matching_shows = sign_up_form.matching_shows.includes(:location).to_a
    new_show_ids = new_matching_shows.map(&:id).to_set

    # Calculate differences
    shows_to_add = new_matching_shows.reject { |s| current_show_ids.include?(s.id) }
    instances_to_remove = current_instances.select { |i| !new_show_ids.include?(i.show_id) }

    # Check for affected registrations
    affected_registrations = []
    instances_to_remove.each do |instance|
      instance.sign_up_slots.each do |slot|
        slot.sign_up_registrations.active.includes(:person).each do |reg|
          affected_registrations << {
            registration: reg,
            instance: instance,
            show: instance.show,
            slot: slot,
            display_name: reg.display_name,
            person: reg.person
          }
        end
      end
    end

    {
      has_changes: shows_to_add.any? || instances_to_remove.any?,
      current_show_count: current_instances.count,
      new_show_count: current_instances.count - instances_to_remove.count + shows_to_add.count,
      shows_to_add: shows_to_add,
      shows_to_add_count: shows_to_add.count,
      instances_to_remove: instances_to_remove,
      instances_to_remove_count: instances_to_remove.count,
      current_instances: current_instances.sort_by { |i| i.show&.date_and_time || Time.current },
      new_matching_shows: new_matching_shows.sort_by(&:date_and_time),
      affected_registrations: affected_registrations,
      has_affected_registrations: affected_registrations.any?,
      total_affected_registration_count: affected_registrations.count
    }
  end

  # Check if event associations will change based on pending settings
  def events_will_change?(pending_params = {})
    return false unless sign_up_form.repeated?

    # Get current state
    current_show_ids = sign_up_form.sign_up_form_instances.pluck(:show_id).to_set

    # Build a temporary form with the new settings to check matching_shows
    test_form = sign_up_form.dup
    test_form.assign_attributes(pending_params.slice(:event_matching, :event_type_filter))

    # Check what would match with new settings
    new_matching_show_ids = matching_shows_for_settings(
      test_form.event_matching,
      test_form.event_type_filter
    ).pluck(:id).to_set

    # Compare
    current_show_ids != new_matching_show_ids
  end

  # Apply event changes - create and remove instances as needed
  # Options:
  #   affected_registration_action: :cancel (default) - how to handle registrations on removed instances
  def apply_event_changes!(affected_registration_action: :cancel)
    return { success: true, created: 0, removed: 0 } unless sign_up_form.repeated?

    analysis = analyze_event_changes
    return { success: true, created: 0, removed: 0 } unless analysis[:has_changes]

    created_count = 0
    removed_count = 0

    ActiveRecord::Base.transaction do
      # Handle instances being removed
      analysis[:instances_to_remove].each do |instance|
        handle_instance_removal(instance, affected_registration_action)
        removed_count += 1
      end

      # Create instances for new shows
      slot_service = SlotManagementService.new(sign_up_form)
      analysis[:shows_to_add].each do |show|
        slot_service.create_instance_for_show!(show)
        created_count += 1
      rescue StandardError => e
        @errors << "Failed to create instance for show #{show.id}: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end

    if errors.empty?
      { success: true, created: created_count, removed: removed_count }
    else
      { success: false, errors: errors, created: 0, removed: 0 }
    end
  end

  # Sync instances without confirmation - used for initial setup or forced sync
  def sync_instances!
    apply_event_changes!(affected_registration_action: :cancel)
  end

  private

  def empty_analysis
    {
      has_changes: false,
      current_show_count: 0,
      new_show_count: 0,
      shows_to_add: [],
      shows_to_add_count: 0,
      instances_to_remove: [],
      instances_to_remove_count: 0,
      current_instances: [],
      new_matching_shows: [],
      affected_registrations: [],
      has_affected_registrations: false,
      total_affected_registration_count: 0
    }
  end

  def matching_shows_for_settings(event_matching, event_type_filter)
    base_scope = sign_up_form.production.shows
                              .where(canceled: false)
                              .where("date_and_time > ?", Time.current)

    case event_matching
    when "all"
      base_scope
    when "event_types"
      return base_scope if event_type_filter.blank?
      base_scope.where(event_type: event_type_filter)
    when "manual"
      base_scope.where(id: sign_up_form.sign_up_form_shows.select(:show_id))
    else
      Show.none
    end
  end

  def handle_instance_removal(instance, action)
    # First, handle any active registrations
    instance.sign_up_slots.each do |slot|
      slot.sign_up_registrations.active.find_each do |reg|
        case action
        when :cancel
          reg.update!(status: "cancelled", cancellation_reason: "Event removed from sign-up form")
        when :keep
          # Leave as-is, the orphaned slot/registration will be cleaned up or shown as historical
        end
      end
    end

    # Destroy the instance (cascades to slots)
    instance.destroy!
  end
end
