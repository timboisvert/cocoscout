# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method
  include ActivityTracking
  include AppUsageTracking
  include SentryContext
  include Impersonation

  helper_method :turbo_native_app?
  layout :resolve_layout

  before_action :track_my_dashboard
  before_action :show_my_sidebar

  def track_my_dashboard
    # Only track if user is on a My:: controller page (not AuthController or other base controllers)
    return unless self.class.name.start_with?("My::") && Current.user.present?
    # And only a real page load: the app's own calls (its push token, a
    # frame, a prefetch) land on My:: controllers too and must not flip the
    # mode under someone working in production mode.
    return unless real_page_load?

    # Leaving production mode: this page says so, once
    # (shared/navigation/mode_switch_notice; Tim, 2026-10-21).
    note_leaving_production_mode

    last_dashboard_prefs = cookies.encrypted[:last_dashboard]
    # Reset if it's an old string value instead of a hash
    last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
    last_dashboard_prefs[Current.user.id.to_s] = "my"
    cookies.encrypted[:last_dashboard] = { value: last_dashboard_prefs, expires: 1.year.from_now }
    remember_mode("my")
  end

  # The mode this person was last in, from the cookie, else their account
  # (users.last_mode); OrganizationContext has the fuller version for pages
  # that also need the organization.
  def note_leaving_production_mode
    prefs = cookies.encrypted[:last_dashboard]
    remembered = prefs.is_a?(Hash) ? prefs[Current.user.id.to_s] : nil
    return unless (remembered || Current.user.last_mode) == "manage"

    organization_id = session[:current_organization_id].is_a?(Hash) ? session[:current_organization_id][Current.user.id.to_s] : nil
    @left_production_mode = Organization.find_by(id: organization_id)&.name || true
  end

  # A page someone actually opened: a GET for HTML, not a Turbo frame, not a
  # prefetch. The mode trackers count nothing else.
  def real_page_load?
    return false unless request.get? && request.format.html? && request.headers["Turbo-Frame"].blank?

    !(request.headers["Sec-Purpose"].to_s.include?("prefetch") || request.headers["X-Sec-Purpose"].to_s.include?("prefetch") || request.headers["Purpose"].to_s == "prefetch")
  end

  # The mode on the account too (users.last_mode; V1.1 plan §8), so a new
  # phone opens where this person works: only on a real page load, and only
  # when it changed.
  def remember_mode(mode)
    return unless Current.user && real_page_load?
    return if Current.user.last_mode == mode

    Current.user.update_column(:last_mode, mode) # rubocop:disable Rails/SkipsModelValidations -- a remembered preference, no callbacks wanted
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
