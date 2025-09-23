class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Try again later." }

  skip_before_action :show_app_sidebar

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to(session.delete(:return_to) || dashboard_path) and return
    else
      @error = true
      render :new, status: :unprocessable_entity
    end
  end

  def signout
    terminate_session
    redirect_to dashboard_path
  end
end
