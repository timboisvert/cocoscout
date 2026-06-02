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
  belongs_to :lead_producer, class_name: "User",
                             foreign_key: :lead_producer_user_id, optional: true
  belongs_to :last_verified_by, class_name: "User",
                                foreign_key: :last_verified_by_user_id, optional: true

  has_many :mic_taggings, dependent: :destroy
  has_many :tags, through: :mic_taggings, source: :mic_tag
  has_many :mic_edits, dependent: :destroy
  has_many :mic_producers, dependent: :destroy
  has_many :producers, through: :mic_producers, source: :user
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
  #  * weekly                — every week on `day_of_week`
  #  * biweekly              — every 2 weeks on `day_of_week`,
  #                            phased to `recurrence_anchor_date`
  #  * monthly_nth_weekday   — every month on the Nth `day_of_week`
  #                            (recurrence_nth_week, where -1 = last)
  #  * monthly_day_of_month  — every month on `recurrence_day_of_month`
  enum :recurrence_pattern, {
    weekly: 0,
    biweekly: 1,
    monthly_nth_weekday: 2,
    monthly_day_of_month: 3
  }, prefix: :recurrence

  validates :name, presence: true, length: { maximum: 200 }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "must be lowercase a-z, digits, and hyphens" },
                   length: { maximum: 120 }
  validates :day_of_week, inclusion: { in: 0..6, allow_nil: true }

  before_validation :assign_slug, on: :create

  scope :active, -> { where(status: statuses[:active], pending: false) }
  scope :pending_moderation, -> { where(pending: true) }
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

  # Has any approved producer.
  def claimed?
    mic_producers.any?
  end

  # Can this user edit this mic? Three paths:
  #   1. superadmin
  #   2. has a MicProducer row on this mic
  #   3. is an editor (captain) of this mic's hub
  def manageable_by?(user)
    return false unless user
    return true if user.respond_to?(:superadmin?) && user.superadmin?
    return true if mic_producers.where(user_id: user.id).exists?
    hub = venue&.city_hub
    hub && hub.editor?(user)
  end
  scope :in_city, ->(city, state) {
    joins(:venue).where(venues: { city: city, state: state })
  }

  # True iff this Mic is linked to a Production with an active open-mic
  # SignUpForm. Drives the "Powered by CocoScout" badge.
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
        { starts_at: s.date_and_time, mic_status: s.mic_status, source: :show, show: s }
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

  # Computed occurrences for the next `limit` matching dates, based on
  # the structured recurrence_pattern. One-off statuses are merged in.
  def compute_occurrences(limit:)
    return [] unless starts_local_time.present?
    tz = venue&.timezone.presence || "America/Chicago"
    Time.use_zone(tz) do
      today = Time.zone.today
      horizon = today + 730 # 2 years cap; cheap
      dates = upcoming_dates(starting_from: today, until_date: horizon, limit: limit)
      dates.map do |d|
        starts_at = Time.zone.local(d.year, d.month, d.day,
                                    starts_local_time.hour, starts_local_time.min)
        override = mic_occurrence_statuses.find_by(occurs_on: d)
        { starts_at: starts_at, mic_status: override&.status, source: :computed, show: nil }
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
        if d && d >= starting_from && (pause_through.blank? || d > pause_through)
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
        if d && d >= starting_from && (pause_through.blank? || d > pause_through)
          dates << d
        end
        m = m.next_month
      end
      dates
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
      out << cur if pause_through.blank? || cur > pause_through
      cur += step_days
    end
    out
  end

  def assign_slug
    return if slug.present?
    base = [ venue&.name, day_name_short ].compact.map { |s| s.to_s.parameterize }.reject(&:blank?).join("-")
    base = name.parameterize.first(60) if base.blank?
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
end
