# frozen_string_literal: true

# Can this person work this stretch of time? Answered from their
# StaffAvailabilityEntry rows, and never as a bare yes/no.
#
#   :free     — they're available for the whole span
#   :partial  — available for some of it (free_from / free_until say which part)
#   :blocked  — available for none of it
#   :unknown  — nothing they've said touches it, and they've never told us
#               anything at all. Treated as free, reported as unconfirmed.
#
# The span is compared whole. The old model tested only a shift's start time,
# so a 4pm–1am shift was never flagged against a blocked evening.
#
# Which entry speaks for a stretch of time, most specific first:
#   a dated entry beats a weekly one; a shorter date span beats a longer one;
#   a narrower band beats a wider one; an exact tie goes to UNAVAILABLE (the
#   conservative answer); the newest entry breaks any tie left.
# Time no entry touches is available — people are presumed around until they
# say otherwise.
#
# Load once for a set of people and a date window, then ask about as many
# shifts as you like:
#
#   resolver = StaffAvailabilityResolver.new(person_ids, from: week_start, to: week_end)
#   resolver.verdict(person_id, shift.starts_at, shift.ends_at)
class StaffAvailabilityResolver
  Verdict = Struct.new(:status, :available_minutes, :total_minutes, :free_from, :free_until, :reasons,
                       keyword_init: true) do
    def free? = status == :free
    def partial? = status == :partial
    def blocked? = status == :blocked
    def unknown? = status == :unknown

    # Available for all of it, or never said otherwise.
    def can_work_all? = free? || unknown?

    # The answer the old boolean gave: is something they've said in the way?
    def flagged? = blocked? || partial?
  end

  # One entry laid onto one calendar day: minutes from that day's midnight.
  Piece = Struct.new(:date, :from, :to, :entry)

  DAY = StaffAvailabilityEntry::DAY

  def initialize(people_or_ids, from:, to:)
    @person_ids = Array(people_or_ids).map { |p| p.respond_to?(:id) ? p.id : p }.compact.uniq
    # A day either side: a band past midnight lands on the next day, and a shift
    # can start the evening before the window.
    @window = (from.to_date - 1)..(to.to_date + 1)
  end

  def verdict(person_id, starts_at, ends_at)
    total = ((ends_at - starts_at) / 60).round
    return Verdict.new(status: :free, available_minutes: 0, total_minutes: 0, reasons: []) if total <= 0

    segments = day_slices(starts_at, ends_at).flat_map { |date, a, b| sweep(person_id, date, a, b) }
    available = segments.sum { |s| s[:available] ? s[:b] - s[:a] : 0 }

    status =
      if available >= total then :free
      elsif available.zero? then :blocked
      else :partial
      end
    status = :unknown if status == :free && segments.none? { |s| s[:winner] } && !told_us_anything?(person_id)

    first_free = segments.find { |s| s[:available] }
    last_free = segments.reverse.find { |s| s[:available] }
    Verdict.new(
      status: status,
      available_minutes: available,
      total_minutes: total,
      free_from: (status == :partial && !segments.first[:available] && first_free) ? at(first_free[:date], first_free[:a]) : nil,
      free_until: (status == :partial && !segments.last[:available] && last_free) ? at(last_free[:date], last_free[:b]) : nil,
      reasons: segments.reject { |s| s[:available] }.filter_map { |s| s[:winner] }.uniq
    )
  end

  # The shape of one calendar day: the stretches they can work (minutes from
  # that midnight, merged), and how the day reads as a whole. Drives the
  # month calendar and the manager's day bars.
  Day = Struct.new(:date, :status, :windows, keyword_init: true) do
    def free? = status == :free
    def partial? = status == :partial
    def blocked? = status == :blocked
    def unknown? = status == :unknown
  end

  def day(person_id, date)
    segments = sweep(person_id, date, 0, DAY)
    windows = segments.select { |s| s[:available] }.map { |s| [ s[:a], s[:b] ] }
                      .each_with_object([]) do |(a, b), merged|
      if merged.any? && merged.last[1] == a
        merged.last[1] = b
      else
        merged << [ a, b ]
      end
    end

    status =
      if windows == [ [ 0, DAY ] ] then :free
      elsif windows.empty? then :blocked
      else :partial
      end
    status = :unknown if status == :free && segments.none? { |s| s[:winner] } && !told_us_anything?(person_id)
    Day.new(date: date, status: status, windows: windows)
  end

  private

  # Cut a span at local midnights: [[date, from_minute, to_minute], ...].
  def day_slices(starts_at, ends_at)
    slices = []
    cursor = starts_at
    while cursor < ends_at
      date = cursor.to_date
      next_midnight = Time.zone.local(date.year, date.month, date.day) + 1.day
      stop = [ ends_at, next_midnight ].min
      slices << [ date, minute_of(cursor, date), minute_of(stop, date) ]
      cursor = stop
    end
    slices
  end

  # Minutes from `date`'s midnight; the next midnight comes out as 1440.
  def minute_of(time, date)
    ((time - Time.zone.local(date.year, date.month, date.day)) / 60).round
  end

  # Split [a, b) on this date at every edge of every piece that touches it, and
  # let the most specific piece speak for each stretch.
  def sweep(person_id, date, a, b)
    live = pieces_for(person_id).select { |p| p.date == date && p.from < b && p.to > a }
    cuts = ([ a, b ] + live.flat_map { |p| [ p.from, p.to ] }).select { |m| m >= a && m <= b }.uniq.sort

    cuts.each_cons(2).map do |x, y|
      active = live.select { |p| p.from <= x && p.to >= y }
      winner = pick(active)&.entry
      { date: date, a: x, b: y, winner: winner, available: winner ? winner.available? : true }
    end
  end

  def pick(pieces)
    pieces.min_by do |p|
      e = p.entry
      [ e.dated? ? 0 : 1, e.span_days, e.band_minutes, e.unavailable? ? 0 : 1, -e.id.to_i ]
    end
  end

  def pieces_for(person_id)
    @pieces ||= {}
    @pieces[person_id] ||= entries_by_person.fetch(person_id, []).flat_map do |entry|
      entry.dates_within(@window).flat_map do |date|
        head = Piece.new(date, entry.starts_minute, [ entry.ends_minute, DAY ].min, entry)
        next [ head ] unless entry.ends_minute > DAY

        # The part past midnight belongs to the next day.
        [ head, Piece.new(date + 1, 0, entry.ends_minute - DAY, entry) ]
      end
    end
  end

  def entries_by_person
    @entries_by_person ||= StaffAvailabilityEntry.where(person_id: @person_ids).touching(@window).group_by(&:person_id)
  end

  def told_us_anything?(person_id)
    @told ||= begin
      with_entries = StaffAvailabilityEntry.where(person_id: @person_ids).distinct.pluck(:person_id)
      confirmed = Person.where(id: @person_ids).where.not(availability_confirmed_through: nil).pluck(:id)
      (with_entries + confirmed).to_set
    end
    @told.include?(person_id)
  end

  def at(date, minute)
    Time.zone.local(date.year, date.month, date.day) + minute.minutes
  end
end
