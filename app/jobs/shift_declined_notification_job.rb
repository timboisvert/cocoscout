# frozen_string_literal: true

# Tells the org's chosen staffing managers, via in-app message, that a staff
# member marked a shift "can't make it" — the counterpart to show can't-make-its
# notifying producers. Runs in the background off the decline request. No-ops
# when the org selected no recipients, or if the decline was undone before the
# job ran. Attributed as an automated notification (message_type: :system).
class ShiftDeclinedNotificationJob < ApplicationJob
  queue_as :default

  def perform(shift_assignment_id)
    assignment = ShiftAssignment.find_by(id: shift_assignment_id)
    return unless assignment&.declined?

    shift = assignment.shift
    organization = shift.organization
    recipients = organization.staffing_notification_recipients
    return if recipients.empty?

    scheduling_url = Rails.application.routes.url_helpers.manage_staffing_scheduling_path(
      week_start: shift.starts_at.to_date.beginning_of_week.iso8601,
      anchor: "day-#{shift.starts_at.to_date.iso8601}"
    )

    ContentTemplateService.deliver(
      template_key: "shift_declined_manager",
      variables: {
        person_name: assignment.person.name,
        role_name: shift.house_role&.name || "staff",
        shift_time: shift.starts_at.strftime("%A, %B %-d at %-l:%M %p"),
        decline_reason: assignment.decline_reason.presence,
        organization_name: organization.name,
        scheduling_url: scheduling_url
      }.compact,
      sender: nil,
      recipients: recipients,
      organization: organization,
      message_type: :system,
      # This notification is FOR managers — system_generated would hide it from
      # the /manage/messages inbox. The :system message type alone keeps the
      # automated attribution.
      system_generated: false
    )
  end
end
