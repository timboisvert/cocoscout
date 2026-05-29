# frozen_string_literal: true

# A date on which a person has marked themselves unavailable to work house
# shifts. Person-level (applies across every org they staff). The scope lets
# them block the whole day or just day/evening shifts.
#
# "Available" everywhere in the Staffing module simply means *not* covered by
# one of these records.
class StaffUnavailability < ApplicationRecord
  belongs_to :person

  # A shift counts as "evening" when it starts at or after this hour (local).
  EVENING_START_HOUR = 17

  enum :scope, {
    all_day: 0,
    day_shifts: 1,
    evening_shifts: 2
  }, default: :all_day

  validates :date, presence: true
  validates :person_id, uniqueness: { scope: :date }

  # :day or :evening for a given time.
  def self.day_part_for(time)
    time.hour >= EVENING_START_HOUR ? :evening : :day
  end

  # Does this record block a shift in the given day part (:day/:evening)?
  def covers_day_part?(part)
    all_day? || (day_shifts? && part == :day) || (evening_shifts? && part == :evening)
  end

  def covers_shift?(shift)
    covers_day_part?(self.class.day_part_for(shift.starts_at))
  end

  # Short human label for the scope.
  def scope_label
    case scope
    when "day_shifts" then "Afternoon"
    when "evening_shifts" then "Evening"
    else "All day"
    end
  end
end
