# frozen_string_literal: true

# A pending "no longer scheduled" notice: a person came off a shift they had
# been told about, or could have seen on My Shifts (any shift of a published
# week), or the shift was deleted or moved to another week. The next Notify
# updates for that week tells them. `notified_at` stamps once sent.
class StaffScheduleRemoval < ApplicationRecord
  belongs_to :organization
  belongs_to :person

  scope :pending, -> { where(notified_at: nil) }

  # Record one for an assignment that's coming off, when the person knew or
  # could have known about the shift. Someone who said they can't make it
  # gets none: they dropped it themselves.
  def self.record!(assignment, shift: assignment.shift)
    return nil if assignment.declined?
    return nil unless assignment.notified_at.present? || StaffingFinalization.published?(shift.organization, shift.starts_at)

    shift.organization.staff_schedule_removals.create!(
      person_id: assignment.person_id,
      shift_starts_at: assignment.told_starts_at || shift.starts_at,
      shift_ends_at: assignment.told_ends_at || shift.ends_at,
      shift_label: assignment.told_role_label.presence || shift.role_label,
      location_name: assignment.told_location_name.presence || shift.location_name
    )
  end

  def hours
    shift_ends_at ? ShiftWords.hours(shift_starts_at, shift_ends_at) : ShiftWords.start_time(shift_starts_at)
  end

  # One list item, like a shift's but with nothing to land on.
  def list_item
    e = ->(s) { ERB::Util.html_escape(s) }
    "<li style=\"margin-bottom:6px;\"><strong>#{e.call(ShiftWords.day(shift_starts_at))}</strong> · #{e.call(hours)} · #{e.call(shift_label.to_s)}" \
      "#{location_name.present? ? " · #{e.call(location_name)}" : ''}</li>"
  end
end
