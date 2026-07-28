# frozen_string_literal: true

# A pending "your shift was removed" notice. Created when an already-notified
# ShiftAssignment is unassigned or its shift deleted, so the next targeted
# "Notify updates" tells the affected person. `notified_at` stamps once sent.
class StaffScheduleRemoval < ApplicationRecord
  belongs_to :organization
  belongs_to :person

  scope :pending, -> { where(notified_at: nil) }
end
