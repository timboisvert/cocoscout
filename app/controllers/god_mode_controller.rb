class GodModeController < ApplicationController
  before_action :require_god_mode, only: [ :index, :impersonate ]

  def index
    @users = User.order(:email_address)
  end

  def impersonate
    user = User.find_by(email_address: params[:email].to_s.strip.downcase)
    if user
      # End any current session and impersonation
      terminate_session
      session[:impersonate_user_id] = user.id
      start_new_session_for user
    end
    redirect_to my_dashboard_path
  end

  def stop_impersonating
    session.delete(:impersonate_user_id)
    terminate_session
    redirect_to my_dashboard_path
  end

  private

  def require_god_mode
    unless Current.user&.god?
      redirect_to my_dashboard_path
    end
  end
end
