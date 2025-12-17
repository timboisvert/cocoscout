# frozen_string_literal: true

class CalendarSyncService
  # Send calendar invitations for a show to all eligible people
  # @param show [Show] The show to send invitations for
  # @param action_type [String] The type of action: "REQUEST", "UPDATE", or "CANCEL"
  def self.notify_for_show(show, action_type = "REQUEST")
    return unless show.present?

    # Don't send notifications for past events unless it's a cancellation
    return if show.date_and_time < Time.current && action_type != "CANCEL"

    # Get all people who have calendar sync enabled for this show's production
    eligible_people = find_eligible_people(show)

    eligible_people.each do |person|
      # Send async to avoid blocking
      CalendarSyncMailer.event_invitation(person, show, action_type).deliver_later
    end
  end

  # Find all people who should receive calendar sync for this show
  def self.find_eligible_people(show)
    production = show.production
    talent_pool = production.talent_pools.first

    return [] unless talent_pool

    # Find people with calendar sync enabled
    people_with_sync = Person.where(calendar_sync_enabled: true, calendar_sync_email_confirmed: true)

    # Get people and groups in the talent pool
    talent_pool_person_ids = talent_pool.people.pluck(:id)
    talent_pool_group_ids = talent_pool.groups.pluck(:id)

    eligible = []

    people_with_sync.includes(:groups).each do |person|
      # Check if person is in talent pool
      next unless talent_pool_person_ids.include?(person.id)

      # Get their sync settings
      sync_entities = person.calendar_sync_entities || {}
      scope = person.calendar_sync_scope || "assignments_only"

      # Check if person entity is enabled
      person_enabled = sync_entities["person"] != false

      # Check if any of their groups are enabled
      person_group_ids = person.groups.pluck(:id)
      enabled_group_ids = person_group_ids.select do |gid|
        sync_entities["group_#{gid}"] == true
      end

      # If scope is "assignments_only", check if they have an assignment
      if scope == "assignments_only"
        has_assignment = false

        # Check person assignment
        if person_enabled
          has_assignment ||= show.show_person_role_assignments.exists?(
            assignable_type: "Person",
            assignable_id: person.id
          )
        end

        # Check group assignments
        if enabled_group_ids.any?
          has_assignment ||= show.show_person_role_assignments.exists?(
            assignable_type: "Group",
            assignable_id: enabled_group_ids
          )
        end

        next unless has_assignment
      end

      # If we get here, person should receive the notification
      eligible << person
    end

    eligible.uniq
  end
end
