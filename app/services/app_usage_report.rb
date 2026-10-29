# frozen_string_literal: true

# The superadmin App usage page (docs/mobile_app_analytics.md): who uses the
# iPhone and Android apps, which builds are still out there, the screens they
# use, and whether people come back. The App Review accounts
# (demo.cocoscout.com) are left out, as everywhere in superadmin.
class AppUsageReport
  EXCLUDED_DOMAIN = SuperadminController::DEMO_EMAIL_DOMAIN
  PLATFORMS = AppActivityDay::PLATFORMS

  def initialize(today: Date.current)
    @today = today
  end

  attr_reader :today

  # Distinct people in the app over the last n days, in all and per platform.
  def active(days)
    scope = days_scope.where(day: (today - (days - 1))..today)
    { total: scope.distinct.count(:user_id) }.merge(scope.group(:platform).distinct.count(:user_id).symbolize_keys)
  end

  # People in the app each day, oldest first: [[date, { "ios" => n, "android" => n }], ...]
  def daily(days = 30)
    counts = days_scope.where(day: (today - (days - 1))..today).group(:day, :platform).distinct.count(:user_id)
    ((today - (days - 1))..today).map do |day|
      [ day, PLATFORMS.index_with { |platform| counts[[ day, platform ]].to_i } ]
    end
  end

  # The builds people used in the last 30 days, per platform, V1 last:
  # [{ platform:, version: "1.1" or "V1", people: n }, ...]
  def versions(days = 30)
    days_scope.where(day: (today - (days - 1))..today).group(:platform, :app_version).distinct.count(:user_id)
              .map { |(platform, version), people| { platform: platform, version: version.presence || "V1", people: people } }
              .sort_by { |row| [ row[:platform], row[:version] == "V1" ? 1 : 0, -row[:people] ] }
  end

  # The most-loaded app screens in the last n days: [[page, views], ...]
  def top_pages(days = 30, limit: 20)
    AppPageDay.where(day: (today - (days - 1))..today).group(:page).order(Arel.sql("SUM(views) DESC")).limit(limit).sum(:views).to_a
  end

  # Of everyone active in the last 30 days (users.last_seen_at), how many used the app.
  def app_share
    active_people = users_scope.where("users.last_seen_at > ?", 30.days.ago).count
    in_app = active(30)[:total]
    { active: active_people, in_app: in_app }
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
    AppActivityDay.joins(:user).merge(users_scope)
  end
end
