# frozen_string_literal: true

# Mirrors a person's old-style availability (staff_unavailabilities + the
# people.availability_mode flag) into StaffAvailabilityEntry rows, so the new
# resolver can be proven against real data before anything reads it.
#
# It rebuilds rather than patches: every `migrated` row for the person is thrown
# away and recreated from the old table. The old table stays the source of
# truth until the new staff screen replaces it, and a full rebuild can't drift.
# Rows from any other source (self_reported, manager) are never touched.
#
# The translation is exact:
#
#   mode "unavailable" (the default — marks are the days you can't work)
#     each mark → a dated UNAVAILABLE band on that date: all day is 0..1440, a
#     region takes the catalog's hours ("evening" 17:00–24:00 → 1020..1440; the
#     overnight "late night" 22:00–02:00 → 1320..1560)
#
#   mode "available" (marks are the ONLY times you can work)
#     seven weekly UNAVAILABLE all-day rows — "normally never" — plus a dated
#     AVAILABLE band per mark. A date beats a weekday, so each mark opens up
#     exactly the time it named, and someone with no marks at all still means
#     "never", as they did.
class StaffAvailabilityBackfill
  def self.rebuild!(person)
    new(person).rebuild!
  end

  # Everyone who has anything to carry over. Idempotent — safe to run again.
  def self.rebuild_all!
    ids = StaffUnavailability.distinct.pluck(:person_id) |
          Person.where(availability_mode: "available").pluck(:id)
    Person.where(id: ids).find_each { |person| rebuild!(person) }
    ids.size
  end

  def initialize(person)
    @person = person
  end

  def rebuild!
    now = Time.current
    rows = []

    available_mode = @person.availability_mode == "available"
    if available_mode
      7.times do |wday|
        rows << row(kind: :weekly, polarity: :unavailable, day_of_week: wday,
                    starts_minute: 0, ends_minute: StaffAvailabilityEntry::DAY, now: now)
      end
    end

    @person.staff_unavailabilities.order(:date).each do |mark|
      from, to = minutes_for(mark.day_part_key)
      next if from.nil?

      rows << row(kind: :dated, polarity: available_mode ? :available : :unavailable,
                  starts_on: mark.date, ends_on: mark.date, starts_minute: from, ends_minute: to, now: now)
    end

    StaffAvailabilityEntry.transaction do
      @person.staff_availability_entries.migrated.delete_all
      StaffAvailabilityEntry.insert_all!(rows) if rows.any?
    end
    rows.size
  end

  private

  # The region's hours as minutes. A region that runs past midnight ends above
  # 1440 instead of wrapping.
  def minutes_for(day_part_key)
    return [ 0, StaffAvailabilityEntry::DAY ] if day_part_key.blank?

    part = StaffingDayParts::STAFFING_DAY_PART_CATALOG.find { |p| p["key"] == day_part_key.to_s }
    return nil unless part

    from = Organization.minute_of_day(part["starts"])
    to = Organization.minute_of_day(part["ends"])
    to += StaffAvailabilityEntry::DAY if to <= from
    [ from, to ]
  end

  def row(kind:, polarity:, starts_minute:, ends_minute:, now:, day_of_week: nil, starts_on: nil, ends_on: nil)
    {
      person_id: @person.id,
      kind: StaffAvailabilityEntry.kinds.fetch(kind.to_s),
      polarity: StaffAvailabilityEntry.polarities.fetch(polarity.to_s),
      source: StaffAvailabilityEntry.sources.fetch("migrated"),
      day_of_week: day_of_week,
      starts_on: starts_on,
      ends_on: ends_on,
      starts_minute: starts_minute,
      ends_minute: ends_minute,
      created_at: now,
      updated_at: now
    }
  end
end
