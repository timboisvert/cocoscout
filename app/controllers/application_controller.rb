# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method
  include ActivityTracking
  include SentryContext

  helper_method :turbo_native_app?
  layout :resolve_layout

  before_action :track_my_dashboard
  before_action :show_my_sidebar

  def track_my_dashboard
    # Only track if user is on a My:: controller page (not AuthController or other base controllers)
    return unless self.class.name.start_with?("My::") && Current.user.present?

    last_dashboard_prefs = cookies.encrypted[:last_dashboard]
    # Reset if it's an old string value instead of a hash
    last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
    last_dashboard_prefs[Current.user.id.to_s] = "my"
    cookies.encrypted[:last_dashboard] = { value: last_dashboard_prefs, expires: 1.year.from_now }
  end

  def show_my_sidebar
    @show_my_sidebar = true if Current.user.present?
  end

  private

  def require_superadmin
    return if Current.user&.superadmin?

    redirect_to my_dashboard_path
  end

  def turbo_native_app?
    request.user_agent.to_s.include?("Turbo Native")
  end

  def resolve_layout
    turbo_native_app? ? "native" : "application"
  end
end
