# frozen_string_literal: true

# A person's availability read back in the words they set it in — the usual
# week as seven answers, and the exceptions as a list — for the staff page,
# the My Shifts card and the manager's overview. StaffAvailabilityWriter is
# the other half: it writes these same answers.
#
# Each answer is one of the writer's three states (anytime / off / hours) with
# its windows. Entries carried over from the old day-mark model don't always
# fit one (an old "unavailable in the evening" mark leaves the rest of the day
# to the usual week), so an exception can also read :limited — shown as what
# it literally says ("Can't work 5:00 PM – 12:00 AM"), and offered for editing
# as the hours it leaves open.
class WorkAvailabilityPicture
  DAY = StaffAvailabilityEntry::DAY
  # Monday first, like the staffing week.
  WEEK_ORDER = [ 1, 2, 3, 4, 5, 6, 0 ].freeze

  Answer = Struct.new(:state, :windows, :label, :said, :set_by, keyword_init: true) do
    # [{ from: "17:00", to: "00:00" }] for the edit sheet's time fields.
    def window_fields
      windows.map { |a, b| { from: WorkAvailabilityPicture.clock(a), to: WorkAvailabilityPicture.clock(b) } }
    end

    def editable_state = state == :limited ? "hours" : state.to_s
  end

  Weekday = Struct.new(:wday, :name, :short_name, :answer, keyword_init: true)
  DatedAnswer = Struct.new(:starts_on, :ends_on, :answer, :note, keyword_init: true) do
    def single_day? = starts_on == ends_on

    def dates_label
      if single_day?
        starts_on.strftime("%a, %b %-d")
      elsif starts_on.year == ends_on.year && starts_on.month == ends_on.month
        "#{starts_on.strftime('%a, %b %-d')} – #{ends_on.strftime('%-d')}"
      else
        "#{starts_on.strftime('%a, %b %-d')} – #{ends_on.strftime('%a, %b %-d')}"
      end
    end
  end

  def initialize(person, entries: nil, today: Date.current)
    @person = person
    @today = today
    @entries = entries || person.staff_availability_entries.includes(:created_by).to_a
  end

  def week
    @week ||= WEEK_ORDER.map do |wday|
      rows = @entries.select { |e| e.weekly? && e.day_of_week == wday && in_effect?(e) }
      name = Date::DAYNAMES[wday]
      Weekday.new(wday: wday, name: name, short_name: name.first(3), answer: answer_for(rows))
    end
  end

  # Exceptions still to come (or under way), soonest first.
  def exceptions
    @exceptions ||= @entries.select(&:dated?)
                            .group_by { |e| [ e.starts_on, e.ends_on ] }
                            .select { |(_, ends_on), _| ends_on >= @today }
                            .sort_by { |(starts_on, ends_on), _| [ starts_on, ends_on ] }
                            .map do |(starts_on, ends_on), rows|
      DatedAnswer.new(starts_on: starts_on, ends_on: ends_on, answer: answer_for(rows, exception: true),
                    note: rows.filter_map(&:note).first)
    end
  end

  def week_said? = week.any? { |d| d.answer.said }
  def anything_said? = @entries.any? || @person.availability_confirmed_through.present?

  # The usual week in as few lines as it takes: runs of days with the same
  # answer collapse ("Mon – Thu", "Fri, Sat"). [[days_label, answer_label], ...]
  def week_summary
    groups = week.chunk_while { |a, b| a.answer.label == b.answer.label }.to_a
    groups.map do |run|
      days =
        if run.size >= 3 then "#{run.first.short_name} – #{run.last.short_name}"
        else run.map(&:short_name).join(", ")
        end
      [ days, run.first.answer.label ]
    end
  end

  # "5:00 PM – 12:00 AM", "After 8:30 PM", "Until 5:00 PM".
  def self.windows_label(windows)
    windows.map do |a, b|
      if a.zero? && b < DAY then "Until #{StaffAvailabilityEntry.minute_label(b)}"
      elsif b == DAY && a.positive? then "After #{StaffAvailabilityEntry.minute_label(a)}"
      else "#{StaffAvailabilityEntry.minute_label(a)} – #{StaffAvailabilityEntry.minute_label(b)}"
      end
    end.join(", ")
  end

  # 1050 → "17:30"; 1440 and 2880 → "00:00" (a time field has no 24:00).
  def self.clock(minute)
    m = minute.to_i % DAY
    format("%02d:%02d", m / 60, m % 60)
  end

  private

  def in_effect?(entry)
    (entry.starts_on.nil? || entry.starts_on <= @today) && (entry.ends_on.nil? || entry.ends_on >= @today)
  end

  # Read a set of rows the way the resolver would, on one day's own clock.
  def answer_for(rows, exception: false)
    return Answer.new(state: :anytime, windows: [ [ 0, DAY ] ], label: "Anytime", said: false) if rows.empty?

    segments = sweep(rows)
    covered = segments.all? { |s| s[:winner] }
    available = merge(segments.select { |s| s[:winner].nil? || s[:winner].available? }.map { |s| [ s[:a], s[:b], s[:winner] ] })
    windows = available.map { |a, b, _| [ a, b ] }
    set_by = rows.find(&:manager?)&.created_by

    if exception && !covered
      # An old-style partial mark: it only speaks for part of the day.
      spoken = segments.select { |s| s[:winner] }
      blocked = merge(spoken.reject { |s| s[:winner].available? }.map { |s| [ s[:a], s[:b], nil ] }).map { |a, b, _| [ a, b ] }
      open = merge(spoken.select { |s| s[:winner].available? }.map { |s| [ s[:a], s[:b], s[:winner] ] }).map { |a, b, _| [ a, b ] }
      label = [
        (open.any? ? "Can work #{plain_windows(open)}" : nil),
        (blocked.any? ? "Can't work #{plain_windows(blocked)}" : nil)
      ].compact.join(" · ")
      return Answer.new(state: :limited, windows: open.presence || complement(blocked), label: label, said: true, set_by: set_by)
    end

    if windows == [ [ 0, DAY ] ]
      Answer.new(state: :anytime, windows: windows, label: "Anytime", said: true, set_by: set_by)
    elsif windows.empty?
      Answer.new(state: :off, windows: [], label: "Not working", said: true, set_by: set_by)
    else
      windows = extend_past_midnight(available)
      Answer.new(state: :hours, windows: windows, label: self.class.windows_label(windows), said: true, set_by: set_by)
    end
  end

  # Split the day at every row's edges; the most specific row speaks for each
  # stretch (same order as StaffAvailabilityResolver#pick).
  def sweep(rows)
    cuts = ([ 0, DAY ] + rows.flat_map { |r| [ r.starts_minute, [ r.ends_minute, DAY ].min ] }).uniq.sort
    cuts.each_cons(2).map do |a, b|
      live = rows.select { |r| r.starts_minute <= a && r.ends_minute >= b }
      winner = live.min_by { |r| [ r.span_days, r.band_minutes, r.unavailable? ? 0 : 1, -r.id.to_i ] }
      { a: a, b: b, winner: winner }
    end
  end

  # Join touching stretches: [[a, b, winner], ...] → the same, merged.
  def merge(stretches)
    stretches.each_with_object([]) do |(a, b, w), out|
      if out.any? && out.last[1] == a
        out.last[1] = b
        out.last[2] = w
      else
        out << [ a, b, w ]
      end
    end
  end

  # A window that reaches midnight carries on as far as the row behind it
  # does: 10 PM – 2 AM, not 10 PM – 12 AM.
  def extend_past_midnight(available)
    available.map do |a, b, winner|
      b = winner.ends_minute if b == DAY && winner && winner.available? && winner.ends_minute > DAY
      [ a, b ]
    end
  end

  def complement(blocked)
    edges = [ 0 ] + blocked.flatten + [ DAY ]
    edges.each_slice(2).map { |a, b| [ a, b ] }.reject { |a, b| b <= a }
  end

  def plain_windows(windows)
    windows.map { |a, b| "#{StaffAvailabilityEntry.minute_label(a)} – #{StaffAvailabilityEntry.minute_label(b)}" }.join(", ")
  end
end
