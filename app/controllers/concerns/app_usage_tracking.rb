# frozen_string_literal: true

# Counts use of the iPhone and Android apps on our own server
# (docs/mobile_app_analytics.md): a day per person (once a day, throttled by
# a signed cookie like ActivityTracking) and a page counter with no person on
# it. Only real page loads in the app, by a signed-in person, never while a
# superadmin is impersonating. A failure here never fails the page.
module AppUsageTracking
  extend ActiveSupport::Concern

  included do
    after_action :track_app_usage, if: :track_app_usage?
  end

  private

  def track_app_usage?
    Current.user.present? && response.successful? && turbo_native_app? && real_page_load? && !impersonating?
  end

  def track_app_usage
    ua = request.user_agent.to_s
    platform = ua.include?("Android") ? "android" : "ios"
    AppPageDay.count!("#{controller_path}##{action_name}", platform: platform)

    key = "app_day_#{Current.user.id}"
    today = Date.current.iso8601
    return if cookies.signed[key] == today

    AppActivityDay.record!(Current.user, platform: platform, app_version: NativeAppVersion.version(ua), nav: NativeAppVersion.nav(ua))
    cookies.signed[key] = { value: today, expires: 1.day.from_now, httponly: true }
  rescue StandardError => e
    Rails.logger.warn("AppUsageTracking: #{e.class}: #{e.message}")
  end
end
