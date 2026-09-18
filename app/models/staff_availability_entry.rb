# frozen_string_literal: true

# One thing a person has said about when they can work: a band of minutes on a
# set of days, marked available or unavailable.
#
#   weekly — every <day_of_week>, optionally only between starts_on and ends_on
#   dated  — every day from starts_on to ends_on (one date is a 1-day range)
#
# Minutes are counted from local midnight. All day is 0..1440; a band that runs
# past midnight simply goes above 1440 (10pm–2am is 1320..1560), so there's no
# wrap-around rule for anyone to get wrong. This deliberately differs from
# scheduling_rules' `time` columns, which can't hold 24:00 or cross midnight as
# one value. Callers never do clock arithmetic on these: use the *_label
# helpers here, and StaffAvailabilityResolver to ask whether a shift is covered.
#
# Overlapping entries are the point — "weekday evenings" alongside "not this
# Thursday" — so nothing here enforces uniqueness. The resolver decides which
# one speaks for each stretch of time.
class StaffAvailabilityEntry < ApplicationRecord
  DAY = 1440

  belongs_to :person
  belongs_to :created_by, class_name: "User", optional: true

  enum :kind, { weekly: 0, dated: 1 }
  enum :polarity, { unavailable: 0, available: 1 }
  # self_reported: the person said it. manager: someone set it on their behalf.
  # migrated: carried over from staff_unavailabilities (rebuilt, never edited).
  enum :source, { self_reported: 0, manager: 1, migrated: 2 }

  validates :starts_minute, numericality: { only_integer: true, in: 0..DAY }
  validates :ends_minute, numericality: { only_integer: true, in: 1..(DAY * 2) }
  validates :day_of_week, inclusion: { in: 0..6 }, if: :weekly?
  validates :day_of_week, absence: true, if: :dated?
  validates :starts_on, :ends_on, presence: true, if: :dated?
  validates :note, length: { maximum: 140 }
  validate :band_runs_forward
  validate :dates_run_forward

  # Entries that could touch any day in the window: weekly ones still in
  # effect, dated ones overlapping it.
  scope :touching, ->(window) {
    where("staff_availability_entries.starts_on IS NULL OR staff_availability_entries.starts_on <= ?", window.last)
      .where("staff_availability_entries.ends_on IS NULL OR staff_availability_entries.ends_on >= ?", window.first)
  }

  def all_day?
    starts_minute.zero? && ends_minute == DAY
  end

  # Days this entry spans in its own terms — how specific it is. A weekly entry
  # is open-ended, so it's the least specific thing there is.
  def span_days
    return Float::INFINITY if weekly?

    (ends_on - starts_on).to_i + 1
  end

  def band_minutes
    ends_minute - starts_minute
  end

  # The days this entry applies to inside a window, in order.
  def dates_within(window)
    first = [ window.first, starts_on ].compact.max
    last = [ window.last, ends_on ].compact.min
    return [] if first > last

    range = (first..last)
    weekly? ? range.select { |d| d.wday == day_of_week } : range.to_a
  end

  def starts_label
    self.class.minute_label(starts_minute)
  end

  def ends_label
    self.class.minute_label(ends_minute)
  end

  # "All day", or "5:00 PM – 12:00 AM".
  def window_label
    all_day? ? "All day" : "#{starts_label} – #{ends_label}"
  end

  # 1050 → "5:30 PM"; 1440 (and 2880) → "12:00 AM".
  def self.minute_label(minute)
    m = minute.to_i % DAY
    Time.utc(2000, 1, 1, m / 60, m % 60).strftime("%-l:%M %p")
  end

  private

  def band_runs_forward
    return if starts_minute.nil? || ends_minute.nil?

    errors.add(:ends_minute, "must be after the start") if ends_minute <= starts_minute
  end

  def dates_run_forward
    return if starts_on.nil? || ends_on.nil?

    errors.add(:ends_on, "can't be before the start date") if ends_on < starts_on
  end
end
