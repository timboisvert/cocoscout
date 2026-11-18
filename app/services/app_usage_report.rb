# frozen_string_literal: true

# The superadmin App page (docs/mobile_app_analytics.md): who uses the iPhone
# and Android apps, how that's growing, which builds are still out there, the
# screens they use, and whether people come back. Everything is counted on
# our own server (AppUsageTracking); downloads and deletions are the stores'.
# The App Review accounts (demo.cocoscout.com) are left out, as everywhere in
# superadmin.
#
# platform: "ios", "android" or nil for both. days: the period the page
# looks at (the tiles for today, 7 and 30 days stay what they say).
class AppUsageReport
  EXCLUDED_DOMAIN = SuperadminController::DEMO_EMAIL_DOMAIN
  PLATFORMS = AppActivityDay::PLATFORMS
  PERIODS = [ 7, 30, 90 ].freeze

  def initialize(today: Date.current, platform: nil, days: 30)
    @today = today
    @platform = platform.presence_in(PLATFORMS)
    @days = days.to_i.in?(PERIODS) ? days.to_i : 30
  end

  attr_reader :today, :platform, :days

  # The platforms the page is showing.
  def platforms = platform ? [ platform ] : PLATFORMS

  # Distinct people in the app over the last n days, in all and per platform.
  def active(days)
    scope = days_scope.where(day: (today - (days - 1))..today)
    { total: scope.distinct.count(:user_id) }.merge(scope.group(:platform).distinct.count(:user_id).symbolize_keys)
  end

  # The same count for the n days before those, to say which way it's going.
  def active_before(days)
    days_scope.where(day: (today - (2 * days - 1))..(today - days)).distinct.count(:user_id)
  end

  # People in the app each day, oldest first: [[date, { "ios" => n, "android" => n }], ...]
  def daily(days = self.days)
    counts = days_scope.where(day: (today - (days - 1))..today).group(:day, :platform).distinct.count(:user_id)
    ((today - (days - 1))..today).map do |day|
      [ day, platforms.index_with { |name| counts[[ day, name ]].to_i } ]
    end
  end

  # How much of the month's people are in the app on a usual day: the average
  # day's people over the last 30, as a share of everyone in those 30 days.
  def stickiness
    month = active(30)[:total]
    return nil if month.zero?

    average_day = daily(30).sum { |_, counts| counts.values.sum } / 30.0
    (average_day * 100.0 / month).round
  end

  # Everyone who has ever opened the app, in all and per platform (a person
  # counts under the platform of their first day).
  def ever
    firsts = first_days
    { total: firsts.size }.merge(firsts.values.group_by(&:last).transform_values(&:size).symbolize_keys)
  end

  # People new to the app, week by week, oldest first, with the running
  # total of everyone so far: [{ week:, new: { "ios" => n, ... }, total: n }, ...]
  def growth(weeks = 12)
    firsts = first_days.values
    this_week = today.beginning_of_week
    starts = (0...weeks).map { |i| this_week - (weeks - 1 - i).weeks }
    running = firsts.count { |day, _| day < starts.first }
    starts.map do |start|
      fresh = firsts.select { |day, _| day.beginning_of_week == start }
      running += fresh.size
      { week: start, new: platforms.index_with { |name| fresh.count { |_, on| on == name } }, total: running }
    end
  end

  # People new to the app in the last n days, and in the n days before.
  def new_people(days = self.days)
    firsts = first_days.values.map(&:first)
    { now: firsts.count { |day| day > today - days }, before: firsts.count { |day| day > today - 2 * days && day <= today - days } }
  end

  # Phones and tablets with notifications on, per platform (one per sign-in
  # on a device): the closest count we have of the app installed and in use.
  def devices
    scope = DeviceToken.joins(:user).merge(users_scope)
    scope = scope.where(platform: platform) if platform
    counts = scope.group(:platform).count
    { total: counts.values.sum }.merge(counts.symbolize_keys)
  end

  # The builds people used in the period, per platform, V1 last:
  # [{ platform:, version: "1.1" or "V1", people: n }, ...]
  def versions(days = self.days)
    days_scope.where(day: (today - (days - 1))..today).group(:platform, :app_version).distinct.count(:user_id)
              .map { |(platform, version), people| { platform: platform, version: version.presence || "V1", people: people } }
              .sort_by { |row| [ row[:platform], row[:version] == "V1" ? 1 : 0, -row[:people] ] }
  end

  # The most-loaded app screens in the period: [[page, views], ...]
  def top_pages(days = self.days, limit: 25)
    scope = AppPageDay.where(day: (today - (days - 1))..today)
    scope = scope.where(platform: platform) if platform
    scope.group(:page).order(Arel.sql("SUM(views) DESC")).limit(limit).sum(:views).to_a
  end

  # Every screen load in the period, and each day's: [[date, views], ...]
  def page_views(days = self.days)
    scope = AppPageDay.where(day: (today - (days - 1))..today)
    scope = scope.where(platform: platform) if platform
    by_day = scope.group(:day).sum(:views)
    ((today - (days - 1))..today).map { |day| [ day, by_day[day].to_i ] }
  end

  # Of everyone active in the last 30 days (users.last_seen_at), how many used the app.
  def app_share
    active_people = users_scope.where("users.last_seen_at > ?", 30.days.ago).count
    in_app = active(30)[:total]
    { active: active_people, in_app: in_app }
  end

  # The people in the app most days of the period: [[user, days], ...]
  def most_active(days = self.days, limit: 15)
    counts = days_scope.where(day: (today - (days - 1))..today).group(:user_id).count
    top = counts.sort_by { |_, n| -n }.first(limit)
    users = User.where(id: top.map(&:first)).includes(:default_person).index_by(&:id)
    top.filter_map { |id, n| [ users[id], n ] if users[id] }
  end

  # Weekly retention for the last `weeks` cohorts (by the week of each
  # person's first app day): [{ week:, people:, returning: [n_week1, n_week2, ...] }, ...]
  def retention(weeks = 8)
    first_days = days_scope.group(:user_id).minimum(:day)
    this_week = today.beginning_of_week
    starts = (0...weeks).map { |i| this_week - (weeks - 1 - i).weeks }
    rows = days_scope.where(day: starts.first..today).pluck(:user_id, :day)
    weeks_active = rows.group_by(&:first).transform_values { |list| list.map { |(_, day)| day.beginning_of_week }.uniq }
    starts.map do |start|
      cohort = first_days.select { |_, day| day.beginning_of_week == start }.keys
      later = starts.select { |s| s > start }
      { week: start, people: cohort.size,
        returning: later.map { |s| cohort.count { |user_id| weeks_active[user_id]&.include?(s) } } }
    end
  end

  private

  def users_scope
    User.where.not("users.email_address LIKE ?", "%@#{EXCLUDED_DOMAIN}")
  end

  def days_scope
    scope = AppActivityDay.joins(:user).merge(users_scope)
    platform ? scope.where(platform: platform) : scope
  end

  # { user_id => [first day, platform that day] } for everyone ever in the
  # app, on the platform(s) showing.
  def first_days
    @first_days ||= days_scope.order(:day).pluck(:user_id, :day, :platform)
                              .each_with_object({}) { |(user_id, day, on), firsts| firsts[user_id] ||= [ day, on ] }
  end
end
