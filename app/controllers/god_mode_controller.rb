class GodModeController < ApplicationController
  before_action :require_god_mode, only: [ :index, :impersonate ]

  def index
    @users = User.order(:email_address)
  end

  def impersonate
    # Store the current user
    session[:user_doing_the_impersonating] = Current.user.id

    # Get the user being impersonated
    user = User.find_by(email_address: params[:email].to_s.strip.downcase)
    if user
      # Update recent impersonations cookie (store email and name)
      recent = []
      if cookies.encrypted[:recent_impersonations].present?
        begin
          recent = JSON.parse(cookies.encrypted[:recent_impersonations])
        rescue JSON::ParserError
          recent = []
        end
      end
      # Remove if already present, then unshift new record
      recent.reject! { |e| e["email"] == user.email_address }
      recent.unshift({ "email" => user.email_address, "name" => user.person.name })
      # Keep only the 5 most recent
      recent = recent.first(5)
      cookies.encrypted[:recent_impersonations] = {
        value: JSON.generate(recent),
        expires: 30.days.from_now,
        httponly: true
      }

      # End any current session and impersonation
      terminate_session

      # Set the impersonating id and start a new session
      session[:impersonate_user_id] = user.id
      start_new_session_for user
    end

    # Redirect
    redirect_to my_dashboard_path and return
  end

  def stop_impersonating
    # Kill the impersonation session
    terminate_session
    session.delete(:impersonate_user_id)

    # Restore the original user
    if session[:user_doing_the_impersonating]
      original_user = User.find_by(id: session[:user_doing_the_impersonating])
      if original_user
        start_new_session_for original_user
      end
    end

    session.delete(:user_doing_the_impersonating)
    redirect_to my_dashboard_path
  end

  def clear_recent_impersonations
    cookies.delete(:recent_impersonations)
    redirect_to god_mode_path, notice: "Recent impersonations cleared."
  end

  private

  def require_god_mode
    unless Current.user&.god?
      redirect_to my_dashboard_path
    end
  end
end
