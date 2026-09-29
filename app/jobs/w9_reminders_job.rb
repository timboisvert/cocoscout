# frozen_string_literal: true

# Nudges staff who were asked for a W-9 and still haven't sent one — once a
# week, until they do (or a manager marks them as not needing one). Only people
# someone has actually asked are chased; a nudge out of nowhere is noise.
class W9RemindersJob < ApplicationJob
  queue_as :background

  INTERVAL = 7.days

  def perform(now: Time.current)
    OrganizationStaffMember.active
                           .where.not(w9_requested_at: nil)
                           .where(tax_form_exempt: false)
                           .where("w9_last_reminded_at IS NULL OR w9_last_reminded_at <= ?", now - INTERVAL)
                           .includes(:w9_submissions, organization: :tax_setting, person: :user)
                           .find_each do |member|
      next unless member.needs_w9? && StaffW9Requester.requestable?(member)

      StaffW9Requester.call(staff_member: member, sender: nil, reminder: true)
    rescue StandardError => e
      Rails.logger.error("[W9RemindersJob] staff member #{member.id}: #{e.class}: #{e.message}")
    end
  end
end
