# frozen_string_literal: true

# Everything anyone says about when a person can work goes through here, in
# the one vocabulary the screens use for a day:
#
#   anytime — they can work any time that day
#   off     — they can't work that day at all
#   hours   — only inside the windows given ("5 PM – midnight", "10 PM – 2 AM")
#
# Nobody picking these ever chooses "available" or "unavailable" rows; this
# class turns the answer into entries the resolver reads:
#
#   anytime → one AVAILABLE band 0..1440
#   off     → one UNAVAILABLE band 0..1440
#   hours   → one UNAVAILABLE band 0..1440, plus an AVAILABLE band per window.
#             A narrower band beats a wider one, so the windows win inside the
#             day and the rest of it reads as out.
#
# A weekday's answer replaces whatever was said about that weekday before. An
# exception (one date or a range) replaces anything said about exactly the
# same dates, and beats the weekday it falls on because a date always beats a
# weekday.
class StaffAvailabilityWriter
  STATES = %w[anytime off hours].freeze
  DAY = StaffAvailabilityEntry::DAY
  # The longest single exception — a season away, not a standing pattern (the
  # usual week is for those).
  MAX_EXCEPTION_DAYS = 366
  # How far ahead "I've looked at this and it's right" vouches for.
  CONFIRM_DAYS = 60

  class Invalid < StandardError; end

  def initialize(person, source: :self_reported, created_by: nil)
    @person = person
    @source = source.to_sym
    @created_by = created_by
  end

  # Set one or more weekdays (0 = Sunday) to the same answer.
  def set_weekdays!(wdays, state:, windows: [])
    wdays = Array(wdays).map(&:to_i).select { |d| d.between?(0, 6) }.uniq
    raise Invalid, "Pick at least one day." if wdays.empty?

    bands = bands_for(state, windows)
    StaffAvailabilityEntry.transaction do
      StaffAvailabilityEntry.weekly.where(person_id: @person.id, day_of_week: wdays).delete_all
      wdays.each do |wday|
        bands.each { |polarity, from, to| create!(kind: :weekly, day_of_week: wday, polarity: polarity, from: from, to: to) }
      end
      confirm_if_self!
    end
  end

  # Add an exception, or edit one: `replacing` is the [starts_on, ends_on] of
  # the exception being changed, so moving its dates doesn't leave the old
  # one behind.
  def save_exception!(starts_on:, ends_on:, state:, windows: [], note: nil, replacing: nil)
    starts_on = to_date(starts_on)
    ends_on = to_date(ends_on) || starts_on
    raise Invalid, "Pick a date." if starts_on.nil?
    raise Invalid, "The last day can't be before the first." if ends_on < starts_on
    raise Invalid, "That's already in the past." if ends_on < Date.current
    raise Invalid, "Keep an exception under a year — use your usual week for anything longer." if (ends_on - starts_on).to_i >= MAX_EXCEPTION_DAYS

    note = note.to_s.strip.presence
    raise Invalid, "Keep the note to 140 characters." if note && note.length > 140

    bands = bands_for(state, windows)
    StaffAvailabilityEntry.transaction do
      delete_exception(starts_on, ends_on)
      old_from, old_to = Array(replacing).map { |d| to_date(d) }
      delete_exception(old_from, old_to || old_from) if old_from
      bands.each do |polarity, from, to|
        create!(kind: :dated, starts_on: starts_on, ends_on: ends_on, polarity: polarity, from: from, to: to, note: note)
      end
      confirm_if_self!
    end
  end

  def remove_exception!(starts_on:, ends_on:)
    starts_on = to_date(starts_on)
    raise Invalid, "Pick a date." if starts_on.nil?

    StaffAvailabilityEntry.transaction do
      delete_exception(starts_on, to_date(ends_on) || starts_on)
      confirm_if_self!
    end
  end

  # "I've looked, and this is right" — vouches for the next CONFIRM_DAYS days.
  # Never shortens a confirmation already further out.
  def confirm!
    through = Date.current + CONFIRM_DAYS
    current = @person.availability_confirmed_through
    @person.update!(availability_confirmed_through: through) if current.nil? || current < through
  end

  # [{ from: "17:00", to: "00:00" }, ...] (or string-keyed params) → sorted,
  # merged [[from_minute, to_minute], ...]. An end at or before its start runs
  # past midnight: 10 PM – 2 AM is 1320..1560, 5 PM – 12 AM is 1020..1440.
  def self.parse_windows(raw)
    list = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.values : raw
    list = list.values if list.is_a?(Hash)
    windows = Array(list).filter_map do |w|
      w = w.to_h.with_indifferent_access
      from = minute_from(w[:from])
      to = minute_from(w[:to])
      next if from.nil? && to.nil?
      raise Invalid, "Give every window a start and an end time." if from.nil? || to.nil?

      if to == from
        raise Invalid, "A window needs an end time after its start." unless from.zero?

        to = DAY # midnight to midnight: the whole day
      elsif to < from
        to += DAY
      end
      [ from, to ]
    end

    windows.sort.each_with_object([]) do |(a, b), merged|
      if merged.any? && a <= merged.last[1]
        merged.last[1] = [ merged.last[1], b ].max
      else
        merged << [ a, b ]
      end
    end
  end

  # "17:30" → 1050; blank or malformed → nil.
  def self.minute_from(value)
    match = value.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)
    return nil unless match

    hour = match[1].to_i
    min = match[2].to_i
    return nil if hour > 23 || min > 59

    hour * 60 + min
  end

  private

  # [[polarity, from, to], ...] for an answer.
  def bands_for(state, windows)
    state = state.to_s
    raise Invalid, "Choose Anytime, Not at all, or Only certain hours." unless STATES.include?(state)

    case state
    when "anytime" then [ [ :available, 0, DAY ] ]
    when "off" then [ [ :unavailable, 0, DAY ] ]
    else
      windows = windows.is_a?(Array) && windows.all?(Array) ? windows : self.class.parse_windows(windows)
      raise Invalid, "Add the hours you can work, or choose Not at all." if windows.empty?
      # Hours that cover the whole day are just "anytime".
      return [ [ :available, 0, DAY ] ] if windows.any? { |a, b| a.zero? && b >= DAY }

      [ [ :unavailable, 0, DAY ] ] + windows.map { |a, b| [ :available, a, b ] }
    end
  end

  # Through the model rather than the association, so a caller holding this
  # person doesn't keep stale rows in memory after a later delete.
  def create!(kind:, polarity:, from:, to:, day_of_week: nil, starts_on: nil, ends_on: nil, note: nil)
    StaffAvailabilityEntry.create!(
      person_id: @person.id, kind: kind, polarity: polarity, day_of_week: day_of_week,
      starts_on: starts_on, ends_on: ends_on,
      starts_minute: from, ends_minute: to, note: note,
      source: @source, created_by: @created_by
    )
  end

  def delete_exception(starts_on, ends_on)
    StaffAvailabilityEntry.dated.where(person_id: @person.id, starts_on: starts_on, ends_on: ends_on).delete_all
  end

  # Only the person themselves vouches for their availability; a manager
  # putting in what they were told by text doesn't.
  def confirm_if_self!
    confirm! if @source == :self_reported
  end

  def to_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    raise Invalid, "That date doesn't look right."
  end
end
