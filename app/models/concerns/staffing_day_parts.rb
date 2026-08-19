# frozen_string_literal: true

# The work time regions an organization staffs by — Morning, Afternoon,
# Evening, whatever the room calls its stretches of the day — declared in
# Staffing settings and stored on organizations.staffing_day_parts as
#
#   [ { "key" => "morning", "name" => "Morning", "starts" => "06:00", "ends" => "12:00" }, … ]
#
# A shift belongs to the region its start time falls in ("Evening" from 5pm),
# and a staff member's unavailability mark names one region or the whole day
# (StaffUnavailability#day_part_key). "All day" is always there and isn't a
# region. Until an org declares its own, it gets the two the app always had:
# Afternoon before 5pm and Evening from 5pm on.
#
# Keys are the parameterized name; a person's marks are keyed the same way, so
# someone who staffs two rooms that both call 5pm-on "Evening" has one mark
# that both rooms read — and each reads it against its own hours.
module StaffingDayParts
  extend ActiveSupport::Concern

  DEFAULT_STAFFING_DAY_PARTS = [
    { "key" => "afternoon", "name" => "Afternoon", "starts" => "00:00", "ends" => "17:00" },
    { "key" => "evening", "name" => "Evening", "starts" => "17:00", "ends" => "24:00" }
  ].freeze

  MAX_STAFFING_DAY_PARTS = 6

  # The declared regions, or the defaults when none are declared.
  def staffing_day_parts_or_default
    parts = Array(staffing_day_parts).select { |p| p.is_a?(Hash) && p["key"].present? }
    parts.any? ? parts : DEFAULT_STAFFING_DAY_PARTS
  end

  def staffing_day_parts_declared?
    Array(staffing_day_parts).any?
  end

  # The key of the region a time of day falls in, or nil when it falls in a
  # gap (then only an all-day mark covers it). Regions are [starts, ends);
  # one whose end is at or before its start wraps past midnight ("Late" 22:00–02:00).
  def staffing_day_part_for(time)
    return nil unless time

    minute = time.hour * 60 + time.min
    part = staffing_day_parts_or_default.find { |p| self.class.day_part_covers_minute?(p, minute) }
    part && part["key"]
  end

  def staffing_day_part_name(key)
    return "All day" if key.blank?

    part = staffing_day_parts_or_default.find { |p| p["key"] == key.to_s }
    part ? part["name"] : key.to_s.titleize
  end

  # Replace the declared regions from settings-form rows ({ name:, starts:,
  # ends: }); blank rows are dropped, names must be unique, times must be
  # HH:MM. Returns the errors found (empty when saved).
  def update_staffing_day_parts!(rows)
    parts, errors = self.class.build_staffing_day_parts(rows)
    update!(staffing_day_parts: parts) if errors.empty?
    errors
  end

  class_methods do
    def day_part_covers_minute?(part, minute)
      starts = minute_of_day(part["starts"])
      ends = minute_of_day(part["ends"])
      return false if starts.nil? || ends.nil?

      if ends > starts
        minute >= starts && minute < ends
      else
        # Wraps past midnight (or 00:00–24:00 style all-day, which ends == 1440 handles above).
        minute >= starts || minute < ends
      end
    end

    # "17:30" → 1050; "24:00" → 1440; anything else → nil.
    def minute_of_day(value)
      return nil unless value.to_s.match?(/\A\d{1,2}:\d{2}\z/)

      hour, min = value.to_s.split(":").map(&:to_i)
      return 1440 if hour == 24 && min.zero?
      return nil if hour > 23 || min > 59

      hour * 60 + min
    end

    def build_staffing_day_parts(rows)
      rows = rows.is_a?(Hash) ? rows.values : Array(rows)
      parts = []
      errors = []
      rows.each do |row|
        row = row.to_h.stringify_keys
        name = row["name"].to_s.squish
        starts = row["starts"].to_s.strip
        ends = row["ends"].to_s.strip
        next if name.blank? && starts.blank? && ends.blank?

        if name.blank?
          errors << "Every region needs a name."
          next
        end
        if minute_of_day(starts).nil? || minute_of_day(ends).nil?
          errors << "#{name} needs a start and end time."
          next
        end
        # A time input can't say 24:00; 23:59 is how the form says "to the end of the day".
        ends = "24:00" if ends == "23:59"
        key = name.parameterize(separator: "_")
        if parts.any? { |p| p["key"] == key }
          errors << "#{name} is listed twice."
          next
        end
        parts << { "key" => key, "name" => name, "starts" => starts, "ends" => ends }
      end
      errors << "That's more than #{MAX_STAFFING_DAY_PARTS} regions — fold some together." if parts.size > MAX_STAFFING_DAY_PARTS
      [ parts, errors.uniq ]
    end
  end
end
