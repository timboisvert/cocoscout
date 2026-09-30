# frozen_string_literal: true

# Sends a manager's "please confirm your availability" draft to the staff
# members they ticked — off the request thread, one person at a time, so one
# bad address never stops the rest.
class StaffAvailabilityNudgeJob < ApplicationJob
  queue_as :default

  def perform(organization_id, staff_member_ids, subject, body, sender_id = nil)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    sender = sender_id && User.find_by(id: sender_id)
    organization.organization_staff_members.active.where(id: staff_member_ids)
                .includes(person: :user).find_each do |member|
      StaffAvailabilityNudger.call(staff_member: member, sender: sender, subject: subject, body: body)
    rescue StandardError => e
      Rails.logger.error("[StaffAvailabilityNudgeJob] staff member #{member.id}: #{e.class}: #{e.message}")
    end
  end
end
