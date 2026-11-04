# frozen_string_literal: true

# Tells the org's chosen staffing managers that a staff member marked a shift
# "can't make it", with the page where they find cover (the counterpart of a
# cast member's vacancy notice). Enqueued when the vacancy is created; no-ops
# when the org chose no recipients, or if the decline was undone before the
# job ran. Attributed as an automated notice.
class ShiftDeclinedNotificationJob < ApplicationJob
  queue_as :default

  def perform(shift_assignment_id)
    assignment = ShiftAssignment.find_by(id: shift_assignment_id)
    return unless assignment&.declined?

    ShiftVacancyNotificationService.notify_created(assignment)
  end
end
