# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url
    redirect_to signin_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  # Where to land someone who just authenticated (signup, signin, or a
  # password-reset that signs them in). Stashed return paths always win —
  # an invitation, tokened form, or interrupted deep link keeps its promise
  # regardless of how the user ended up authenticating. Otherwise fall back
  # to the dashboard they last used; new users have no cookie entry and
  # default to the talent dashboard.
  def post_authentication_landing_path(user)
    stashed = session.delete(:return_to) || session.delete(:return_to_after_authenticating)
    return stashed if stashed.present?

    last_dashboard_prefs = cookies.encrypted[:last_dashboard]
    last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
    case last_dashboard_prefs[user.id.to_s]
    when "manage" then manage_path
    else my_dashboard_path
    end
  end

  def start_new_session_for(user)
    user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
      Current.session = session
      cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
    end
  end

  def terminate_session
    Current.session.destroy
    cookies.delete(:session_id)
  end
end
