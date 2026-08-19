# frozen_string_literal: true

# The work time regions an organization staffs by — picked from a fixed
# catalog (Early morning, Morning, Late morning … Late night), each with the
# hours it covers. Staffing settings → Work times is a checklist: the org
# turns on the regions it wants offered; organizations.staffing_day_parts
# holds the chosen keys (["morning", "afternoon", "evening"]). Empty means
# the defaults: Morning, Afternoon, Evening. "All day" is always there and
# isn't a region.
#
# A shift belongs to every region whose hours contain its start time (regions
# overlap on purpose — Morning holds Late morning), and a staff member's
# unavailability mark names one region or the whole day
# (StaffUnavailability#day_part_key). Marks are person-level, so someone who
# staffs two rooms has one "evening" mark that both rooms read; a region a
# room hasn't turned on blocks nothing there.
module StaffingDayParts
  extend ActiveSupport::Concern

  # In the order of the day. Times are [starts, ends); "24:00" is midnight;
  # a region whose end is before its start runs past midnight.
  STAFFING_DAY_PART_CATALOG = [
    { "key" => "early_morning", "name" => "Early morning", "starts" => "05:00", "ends" => "09:00" },
    { "key" => "morning", "name" => "Morning", "starts" => "06:00", "ends" => "12:00" },
    { "key" => "late_morning", "name" => "Late morning", "starts" => "10:00", "ends" => "12:00" },
    { "key" => "early_afternoon", "name" => "Early afternoon", "starts" => "12:00", "ends" => "14:00" },
    { "key" => "afternoon", "name" => "Afternoon", "starts" => "12:00", "ends" => "17:00" },
    { "key" => "late_afternoon", "name" => "Late afternoon", "starts" => "15:00", "ends" => "17:00" },
    { "key" => "early_evening", "name" => "Early evening", "starts" => "17:00", "ends" => "19:00" },
    { "key" => "evening", "name" => "Evening", "starts" => "17:00", "ends" => "24:00" },
    { "key" => "late_evening", "name" => "Late evening", "starts" => "21:00", "ends" => "24:00" },
    { "key" => "late_night", "name" => "Late night", "starts" => "22:00", "ends" => "02:00" }
  ].freeze
  STAFFING_DAY_PART_KEYS = STAFFING_DAY_PART_CATALOG.map { |p| p["key"] }.freeze
  DEFAULT_STAFFING_DAY_PART_KEYS = %w[morning afternoon evening].freeze

  # The regions this organization offers, catalog order.
  def staffing_day_parts_or_default
    self.class.staffing_day_parts_for_keys(staffing_day_part_keys)
  end

  # The chosen keys — the defaults until the org has picked its own.
  def staffing_day_part_keys
    keys = Array(staffing_day_parts).map(&:to_s) & STAFFING_DAY_PART_KEYS
    keys.any? ? keys : DEFAULT_STAFFING_DAY_PART_KEYS
  end

  def staffing_day_parts_declared?
    (Array(staffing_day_parts).map(&:to_s) & STAFFING_DAY_PART_KEYS).any?
  end

  # The keys of every offered region a time of day falls in — [] in a gap
  # (then only an all-day mark covers it).
  def staffing_day_part_keys_for(time)
    return [] unless time

    minute = time.hour * 60 + time.min
    staffing_day_parts_or_default.select { |p| self.class.day_part_covers_minute?(p, minute) }.map { |p| p["key"] }
  end

  def staffing_day_part_name(key)
    return "All day" if key.blank?

    part = STAFFING_DAY_PART_CATALOG.find { |p| p["key"] == key.to_s }
    part ? part["name"] : key.to_s.titleize
  end

  # Turn on exactly these regions (unknown keys ignored). An empty pick
  # goes back to the defaults.
  def update_staffing_day_part_keys!(keys)
    chosen = STAFFING_DAY_PART_KEYS & Array(keys).map(&:to_s)
    update!(staffing_day_parts: chosen)
  end

  class_methods do
    # Catalog entries for these keys, in catalog order.
    def staffing_day_parts_for_keys(keys)
      keys = Array(keys).map(&:to_s)
      STAFFING_DAY_PART_CATALOG.select { |p| keys.include?(p["key"]) }
    end

    def day_part_covers_minute?(part, minute)
      starts = minute_of_day(part["starts"])
      ends = minute_of_day(part["ends"])
      return false if starts.nil? || ends.nil?

      if ends > starts
        minute >= starts && minute < ends
      else
        minute >= starts || minute < ends # runs past midnight
      end
    end

    # "17:30" → 1050; "24:00" → 1440.
    def minute_of_day(value)
      hour, min = value.to_s.split(":").map(&:to_i)
      return 1440 if hour == 24 && min.zero?

      hour * 60 + min
    end

    # "5:00 AM – 9:00 AM" for the settings checklist.
    def day_part_hours_label(part)
      fmt = lambda do |hhmm|
        minute = minute_of_day(hhmm) % 1440
        Time.utc(2000, 1, 1, minute / 60, minute % 60).strftime("%-l:%M %p")
      end
      "#{fmt.call(part['starts'])} – #{fmt.call(part['ends'])}"
    end
  end
end
