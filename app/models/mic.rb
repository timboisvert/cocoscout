# frozen_string_literal: true

# The public Open Mic Finder listing — always present, always self-sufficient.
#
# When `production_id` is nil (the default): the Mic's own recurrence + sign-up
# columns are the source of truth. The page renders perfectly without any
# CocoScout Organization/Production/Show/SignUpForm record existing.
#
# When `production_id` is set (post-migration): the Mic page projects schedule
# from the linked Production's upcoming open-mic Shows and sign-up timing from
# the linked SignUpForm. The Mic's own recurrence/sign-up columns are kept
# in place as immutable history.
#
# See docs/mics_finder_plan.md for the full spec.
class Mic < ApplicationRecord
  belongs_to :venue
  belongs_to :production, optional: true
  belongs_to :lead_owner, class_name: "User",
                          foreign_key: :lead_owner_user_id, optional: true
  belongs_to :last_verified_by, class_name: "User",
                                foreign_key: :last_verified_by_user_id, optional: true

  has_many :mic_taggings, dependent: :destroy
  has_many :tags, through: :mic_taggings, source: :mic_tag
  has_many :mic_edits, dependent: :destroy
  has_many :mic_owners, dependent: :destroy
  has_many :owners, through: :mic_owners, source: :user
  has_many :mic_claims, dependent: :destroy
  has_many :mic_challenges, dependent: :destroy
  has_many :mic_suggestions, dependent: :destroy
  has_many :mic_favorites, dependent: :destroy
  has_many :mic_signup_alerts, dependent: :destroy
  has_many :mic_links, dependent: :destroy
  has_many :mic_occurrence_statuses, dependent: :destroy
  has_many :mic_announcements, dependent: :destroy

  enum :status, {
    active: 0,
    dormant: 1,
    ended: 2
  }

  enum :format, {
    standup: 0,
    music: 1,
    poetry: 2,
    open_stage: 3
  }, prefix: :format

  # Sign-up channel: online (form/lottery), in person (sign a sheet,
  # walk up), or both. `bucket_draw` is independent — any of these can
  # also be a bucket-draw.
  enum :signup_method, {
    online: 0,
    in_person: 1,
    online_and_in_person: 2
  }, prefix: :signup

  enum :cost, {
    free: 0,
    drink_minimum: 1,
    pay_to_perform: 2,
    pay_pass_the_hat: 3
  }, prefix: :cost

  # Structured recurrence:
  #  * weekly                 — every week on `day_of_week`
  #  * biweekly               — every 2 weeks on `day_of_week`,
  #                              phased to `recurrence_anchor_date`
  #  * monthly_nth_weekday    — every month on the Nth `day_of_week`
  #                              (recurrence_nth_week, where -1 = last)
  #  * monthly_day_of_month   — every month on `recurrence_day_of_month`
  #  * monthly_nth_weekdays   — every month on SEVERAL `day_of_week`
  #                              instances per month, e.g. 1st & 3rd
  #                              Monday. Uses `recurrence_nth_weeks`,
  #                              a jsonb array of integers like [1, 3]
  #                              (where -1 = last week of month).
  enum :recurrence_pattern, {
    weekly: 0,
    biweekly: 1,
    monthly_nth_weekday: 2,
    monthly_day_of_month: 3,
    monthly_nth_weekdays: 4,
    custom_dates: 5
  }, prefix: :recurrence

  validates :name, presence: true, length: { maximum: 200 }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "must be lowercase a-z, digits, and hyphens" },
                   length: { maximum: 120 }
  validates :day_of_week, inclusion: { in: 0..6, allow_nil: true }

  before_validation :assign_slug, on: :create
  # Form posts can deliver dirty data into the recurrence fields — empty
  # strings from a placeholder hidden input, integer-shaped strings,
  # leftovers from a different sub-pattern. Normalize them on every save
  # so the column is always trustworthy at read time.
  before_save :normalize_recurrence_fields

  scope :active, -> { where(status: statuses[:active], pending: false) }
  scope :pending_moderation, -> { where(pending: true) }
  # Paused mics still exist (search, favorites roster, direct URL) but
  # drop out of city listings / upcoming-event surfaces. Apply
  # `.unpaused` wherever you wouldn't want a hiatusing mic to show up.
  scope :unpaused, -> { where(paused: false) }

  # True iff the mic is paused AND not scheduled to come back within
  # the foreseeable horizon. UI uses this to suppress the upcoming
  # calendar entirely and show a hiatus card instead.
  def on_hiatus?
    return false unless paused
    return true  if canceled_until.blank?
    canceled_until < Date.current
  end
  # Returns mics whose venue rolls up to the given hub (via venue.city_hub_id).
  scope :in_hub, ->(hub) {
    joins(:venue).where(venues: { city_hub_id: hub.id })
  }
  # Haversine filter — mics within `miles` of the given (lat, lng).
  # Ungeocoded venues are excluded when the filter is active.
  scope :within_miles_of, ->(lat, lng, miles) {
    if lat.blank? || lng.blank? || miles.blank?
      all
    else
      joins(:venue).where("venues.lat IS NOT NULL AND venues.lng IS NOT NULL").where(
        "3959 * 2 * asin(sqrt(" \
          "pow(sin(radians((? - venues.lat) / 2)), 2) + " \
          "cos(radians(venues.lat)) * cos(radians(?)) * " \
          "pow(sin(radians((? - venues.lng) / 2)), 2)" \
        ")) <= ?",
        lat, lat, lng, miles
      )
    end
  }

  # Has any approved owner.
  def claimed?
    mic_owners.any?
  end

  # Can this user edit this mic? Three paths:
  #   1. superadmin
  #   2. has a MicOwner row on this mic
  #   3. is an editor (captain) of this mic's hub
  def manageable_by?(user)
    return false unless user
    return true if user.respond_to?(:superadmin?) && user.superadmin?
    return true if mic_owners.where(user_id: user.id).exists?
    hub = venue&.city_hub
    hub && hub.editor?(user)
  end
  scope :in_city, ->(city, state) {
    joins(:venue).where(venues: { city: city, state: state })
  }

  # True iff this Mic is linked to a Production with an active open-mic
  # SignUpForm. Drives the "Powered by CocoScout" badge.
  # True when this mic is already running on CocoScout in some form —
  # either through a real production + sign-up form (the migration
  # wizard), OR via a producer who pasted a CocoScout sign-up URL into
  # the signup_url field manually. Used to suppress the "Migrate to
  # CocoScout" pitch on the producer page when it would be moot.
  def on_cocoscout?
    return true if production_id.present?
    signup_url.to_s.match?(%r{\Ahttps?://(www\.)?cocoscout\.com\b}i)
  end

  def powered_by_cocoscout?
    return false unless production_id
    production&.sign_up_forms&.any? { |f| f.active && Array(f.event_type_filter).include?("open_mic") } || false
  end

  # Display string for "where this happens" — used in row + detail headers.
  def location_text
    venue&.neighborhood_city
  end

  # Next N occurrences in chronological order. Reads from the producer's
  # CocoScout Shows when migrated; falls back to the Mic's own recurrence
  # otherwise. Either way the caller gets `{ starts_at:, mic_status:,
  # source: :show | :computed, show: }` hashes — the view never branches.
  def next_occurrences(limit: 6)
    if production_id
      shows = production.shows
                        .where(event_type: :open_mic)
                        .where("date_and_time >= ?", Time.current)
                        .order(:date_and_time)
                        .limit(limit)
      shows.map do |s|
        { starts_at: s.date_and_time, mic_status: s.mic_status, mic_status_note: nil,
          source: :show, show: s }
      end
    else
      compute_occurrences(limit: limit)
    end
  end

  # True when the URL should be displayed as a sign-up CTA — i.e. the
  # mic has an online channel.
  def online_signup?
    %w[online online_and_in_person].include?(signup_method.to_s)
  end

  # Sign-up timing info, normalized regardless of whether we project through
  # a SignUpForm. Returns nil when nothing is configured.
  def signup_info
    if production_id
      form = production.sign_up_forms.detect { |f| f.active && Array(f.event_type_filter).include?("open_mic") }
      return nil unless form
      {
        url: form.respond_to?(:public_url) ? form.public_url : nil,
        opens_at: form.opens_at,
        opens_at_text: signup_opens_at_text.presence,
        powered_by_cocoscout: true
      }
    elsif signup_url.present? || signup_opens_at_text.present?
      {
        # `signup_url` is overloaded: it's either an actual URL OR a
        # description of where to sign up (e.g. "Online through Lia
        # Berman's FB Google Sheet post"). Surface them on different
        # keys so the detail page can render a button for the link
        # case and an instructional line for the text case. Only do
        # either when the mic actually has an online channel.
        url:          (online_signup? && signup_url_is_link? ? signup_url : nil),
        channel_text: (online_signup? && !signup_url_is_link? ? signup_url.presence : nil),
        opens_at: nil,
        opens_at_text: signup_opens_at_text.presence,
        powered_by_cocoscout: false
      }
    end
  end

  # True when `signup_url` parses as an http(s) URL — i.e. something we
  # can wire up to a "Sign up" button. Otherwise the value is treated
  # as free-text instructions.
  def signup_url_is_link?
    signup_url.to_s.match?(%r{\Ahttps?://}i)
  end

  def to_param
    slug
  end

  private

  # Grace window applied to today's occurrence — a mic shows up as
  # "upcoming" for this long AFTER its start time, then drops off and
  # the next date takes its place. Covers walk-ins, late starts, and
  # the typical open-mic block (~90 min).
  OCCURRENCE_GRACE = 90.minutes

  # Computed occurrences for the next `limit` matching dates, based on
  # the structured recurrence_pattern. One-off statuses are merged in.
  # A paused mic returns nothing unless it has a future resume date
  # (`canceled_until`), in which case the regular schedule silently
  # picks back up on that date — the `iterate`/branches below already
  # treat `canceled_until` as a "skip up to and including" cutoff.
  def compute_occurrences(limit:)
    return [] if paused && (canceled_until.blank? || canceled_until < Date.current)
    tz = venue&.timezone.presence || "America/Chicago"

    if recurrence_pattern.to_s == "custom_dates"
      return custom_date_occurrences(limit: limit, tz: tz)
    end

    return [] unless starts_local_time.present?
    Time.use_zone(tz) do
      today = Time.zone.today
      horizon = today + 730 # 2 years cap; cheap
      # Fetch a small buffer over `limit` so we still hand back enough
      # occurrences after filtering out today's already-finished slot.
      dates = upcoming_dates(starting_from: today, until_date: horizon, limit: limit + 2)
      now = Time.current
      dates.filter_map do |d|
        starts_at = Time.zone.local(d.year, d.month, d.day,
                                    starts_local_time.hour, starts_local_time.min)
        # Skip if this slot already ended (start + grace is in the past).
        # Only today's occurrence can ever hit this branch since future
        # dates' starts_at is always > now.
        next if starts_at + OCCURRENCE_GRACE < now
        override = mic_occurrence_statuses.find_by(occurs_on: d)
        { starts_at: starts_at, mic_status: override&.status,
          mic_status_note: override&.note, source: :computed, show: nil }
      end.first(limit)
    end
  end

  # Each entry in custom_dates carries its own time, so each date can
  # have a different start. Falls back to the mic's global
  # `starts_local_time` for legacy string entries that don't include
  # a time of their own.
  def custom_date_occurrences(limit:, tz:)
    Time.use_zone(tz) do
      now = Time.current
      custom_date_entries.filter_map do |entry|
        d = entry[:date]
        t = entry[:time] || starts_local_time
        next unless d && t
        starts_at = Time.zone.local(d.year, d.month, d.day, t.hour, t.min)
        next if starts_at + OCCURRENCE_GRACE < now
        next if canceled_until.present? && d < canceled_until
        override = mic_occurrence_statuses.find_by(occurs_on: d)
        { starts_at: starts_at, mic_status: override&.status,
          mic_status_note: override&.note, source: :computed, show: nil }
      end.sort_by { |o| o[:starts_at] }.first(limit)
    end
  end

  # Parses the `custom_dates` jsonb column into uniform {date:, time:}
  # entries. Accepts either the new hash form ({"date"=>"2026-06-05",
  # "time"=>"20:00"}) or a bare ISO date string (legacy/fallback).
  public def custom_date_entries
    Array(custom_dates).filter_map do |raw|
      case raw
      when Hash, ActionController::Parameters
        h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
        d = (Date.parse(h["date"].to_s) rescue nil)
        t = (Time.zone.parse("2000-01-01 #{h["time"]}") rescue nil) if h["time"].present?
        d && { date: d, time: t }
      when String
        d = (Date.parse(raw) rescue nil)
        d && { date: d, time: nil }
      end
    end
  end

  # Returns up to `limit` future dates that match the recurrence pattern,
  # skipping any dates on/before `canceled_until`.
  def upcoming_dates(starting_from:, until_date:, limit:)
    pattern = recurrence_pattern || "weekly"
    interval = [ (recurrence_interval || 1), 1 ].max
    pause_through = canceled_until

    case pattern
    when "weekly"
      return [] unless day_of_week
      cur = starting_from
      cur += 1.day until cur.wday == day_of_week
      iterate(cur, until_date, 7 * interval, pause_through, limit)
    when "biweekly"
      return [] unless day_of_week
      cur = starting_from
      cur += 1.day until cur.wday == day_of_week
      anchor = recurrence_anchor_date || cur
      # Advance to the next biweekly date in phase with the anchor.
      cur += 7.days while ((cur - anchor).to_i / 7).odd?
      iterate(cur, until_date, 14, pause_through, limit)
    when "monthly_nth_weekday"
      return [] unless day_of_week && recurrence_nth_week
      dates = []
      m = starting_from.beginning_of_month
      while dates.size < limit && m <= until_date
        d = nth_weekday_of_month(m, day_of_week, recurrence_nth_week)
        if d && d >= starting_from && (pause_through.blank? || d >= pause_through)
          dates << d
        end
        m = m.next_month
      end
      dates
    when "monthly_day_of_month"
      return [] unless recurrence_day_of_month
      dates = []
      m = starting_from.beginning_of_month
      while dates.size < limit && m <= until_date
        d = day_of_month_safe(m, recurrence_day_of_month)
        if d && d >= starting_from && (pause_through.blank? || d >= pause_through)
          dates << d
        end
        m = m.next_month
      end
      dates
    when "monthly_nth_weekdays"
      # Form posts include an empty placeholder so the param key is
      # always present; strip zeros and blanks before computing.
      weeks = Array(recurrence_nth_weeks).map(&:to_i).reject(&:zero?).uniq
      return [] unless day_of_week && weeks.any?
      dates = []
      m = starting_from.beginning_of_month
      while dates.size < limit && m <= until_date
        # Resolve every requested nth-week in this month, then sort —
        # since the user may have specified them out of order ([3, 1]).
        month_dates = weeks.map { |w| nth_weekday_of_month(m, day_of_week, w) }.compact.sort
        month_dates.each do |d|
          break if dates.size >= limit
          dates << d if d >= starting_from && (pause_through.blank? || d >= pause_through)
        end
        m = m.next_month
      end
      dates
    when "custom_dates"
      # Free-form list of explicit dates, each with its own time.
      # Returns just the dates here; per-entry times live on the entries
      # and are used directly by `custom_date_occurrences`.
      custom_date_entries
        .map { |e| e[:date] }
        .compact.sort.uniq
        .select { |d| d >= starting_from && d <= until_date && (pause_through.blank? || d >= pause_through) }
        .first(limit)
    else
      []
    end
  end

  # The Nth `day_of_week` in the month containing `month_start`.
  # `n` is 1..5, or -1 for "last".
  def nth_weekday_of_month(month_start, day_of_week, n)
    if n == -1
      # Last `day_of_week` of the month.
      d = month_start.end_of_month
      d -= 1.day until d.wday == day_of_week
      d
    else
      d = month_start
      d += 1.day until d.wday == day_of_week
      d += (n - 1) * 7
      d.month == month_start.month ? d : nil
    end
  end

  # Returns a valid date for the day-of-month in this month, or nil if
  # it doesn't exist (e.g., Feb 30 → nil).
  def day_of_month_safe(month_start, dom)
    return nil if dom < 1 || dom > 31
    Date.new(month_start.year, month_start.month, dom) rescue nil
  end

  def iterate(cur, until_date, step_days, pause_through, limit)
    out = []
    while out.size < limit && cur <= until_date
      out << cur if pause_through.blank? || cur >= pause_through
      cur += step_days
    end
    out
  end

  def assign_slug
    return if slug.present?
    base = name.to_s.parameterize.first(60)
    base = [ venue&.name, day_name_short ].compact.map { |s| s.to_s.parameterize }.reject(&:blank?).join("-") if base.blank?
    base = "mic" if base.blank?
    candidate = base
    n = 1
    while Mic.where(slug: candidate).exists?
      n += 1
      candidate = "#{base}-#{n}"
    end
    self.slug = candidate
  end

  def day_name_short
    return nil unless day_of_week
    %w[sunday monday tuesday wednesday thursday friday saturday][day_of_week]
  end

  # Clean up the recurrence columns so they never carry stale or junk
  # values across pattern changes. Form posts can include placeholder
  # empties, integer-shaped strings, or values left over from a
  # different sub-pattern; this collapses all of that into one
  # canonical form per pattern.
  def normalize_recurrence_fields
    # recurrence_nth_weeks is always stored as a clean, sorted, unique
    # array of integers in [-1, 1, 2, 3, 4, 5]. Empty + zero get dropped.
    raw = Array(recurrence_nth_weeks).map(&:to_i)
    cleaned = raw.uniq.reject { |n| n == 0 || n < -1 || n > 5 }.sort_by { |n| n == -1 ? 99 : n }
    self.recurrence_nth_weeks = cleaned

    # Fields that don't belong to the chosen pattern get cleared so a
    # pattern swap doesn't leave shrapnel behind that confuses the
    # date-computation branches.
    case recurrence_pattern.to_s
    when "weekly", "biweekly"
      self.recurrence_nth_week     = nil
      self.recurrence_nth_weeks    = []
      self.recurrence_day_of_month = nil
    when "monthly_nth_weekday"
      self.recurrence_nth_weeks    = []
      self.recurrence_day_of_month = nil
    when "monthly_nth_weekdays"
      self.recurrence_nth_week     = nil
      self.recurrence_day_of_month = nil
    when "monthly_day_of_month"
      self.recurrence_nth_week     = nil
      self.recurrence_nth_weeks    = []
    when "custom_dates"
      self.day_of_week             = nil
      self.recurrence_nth_week     = nil
      self.recurrence_nth_weeks    = []
      self.recurrence_day_of_month = nil
    end

    # custom_dates is a jsonb array of {date, time} hashes. Strip
    # entries that don't parse, dedupe by (date, time), and sort. When
    # the pattern isn't custom_dates we clear the list so a swap doesn't
    # leave shrapnel behind.
    if recurrence_pattern.to_s == "custom_dates"
      cleaned = Array(custom_dates).filter_map do |raw|
        h = case raw
        when Hash then raw.transform_keys(&:to_s)
        when ActionController::Parameters then raw.to_unsafe_h.transform_keys(&:to_s)
        when String then { "date" => raw, "time" => nil }
        end
        next unless h
        d = (Date.parse(h["date"].to_s).iso8601 rescue nil)
        next unless d
        time_str = h["time"].to_s.strip.presence
        { "date" => d, "time" => time_str }
      end
      self.custom_dates = cleaned.uniq.sort_by { |e| [ e["date"], e["time"].to_s ] }
    else
      self.custom_dates = []
    end
  end
end
