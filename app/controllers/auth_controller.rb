# frozen_string_literal: true

class AuthController < ApplicationController
  allow_unauthenticated_access only: %i[signup handle_signup signin handle_signin password handle_password reset
                                        handle_reset set_password handle_set_password]
  rate_limit to: 10, within: 3.minutes, only: :handle_signin, with: lambda {
    redirect_to signin_path, alert: "Try again later"
  }
  rate_limit to: 5, within: 10.minutes, only: :handle_password, with: lambda {
    redirect_to password_path, alert: "Too many requests. Please try again later."
  }
  rate_limit to: 10, within: 10.minutes, only: :handle_signup, with: lambda {
    redirect_to signup_path, alert: "Too many signup attempts. Please try again later."
  }

  skip_before_action :track_my_dashboard
  skip_before_action :show_my_sidebar

  def signup
    @user = User.new
  end

  def handle_signup
    # Get the email and show an error if it already exists
    # Remove null bytes to prevent database errors
    normalized_email = user_params[:email_address].to_s.delete("\0").strip.downcase
    if User.exists?(email_address: normalized_email)
      @user = User.new(user_params)
      @user_exists_error = true
      @email_address = normalized_email
      render :signin, status: :unprocessable_entity
      return
    end

    # The user doesn't exist, so create it
    @user = User.new(user_params)
    if @user.save

      # Create the associated person if it doesn't exist
      person = Person.find_by(email: @user.email_address)
      if person.nil?
        person = Person.new(email: @user.email_address, name: @user.email_address.split("@").first, user: @user)
      else
        # The person exists, so just make sure their user and person are tied to each other
        person.user = @user
      end

      # Save the person
      person.save!

      # The user has been created, so log them in
      if User.authenticate_by(user_params.slice(:email_address, :password))
        start_new_session_for @user
        AuthMailer.signup(@user).deliver_later
        AdminMailer.user_account_created(@user).deliver_later

        # Redirect to the last dashboard they were on (defaults to my_dashboard for new signups)
        last_dashboard_prefs = cookies.encrypted[:last_dashboard]
        # Reset if it's an old string value instead of a hash
        last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
        user_preference = last_dashboard_prefs[@user.id.to_s]
        default_path = case user_preference
        when "manage"
                         manage_path
        else
                         my_dashboard_path
        end

        redirect_to(session.delete(:return_to) || default_path) and return
      else
        render :signup, status: :unprocessable_entity
      end
    else
      render :signup, status: :unprocessable_entity
    end
  end

  def signin
    # Store redirect_to param in session if provided (e.g., from invitation accept page)
    if params[:redirect_to].present?
      session[:return_to] = params[:redirect_to]
    end

    # If user is already authenticated, redirect them to their dashboard
    if authenticated?
      last_dashboard_prefs = cookies.encrypted[:last_dashboard]
      last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
      user_preference = last_dashboard_prefs[Current.user.id.to_s]
      default_path = case user_preference
      when "manage"
                       manage_path
      else
                       my_dashboard_path
      end

      redirect_to(session.delete(:return_to) || default_path) and return
    end

    @user = User.new

    if session[:password_reset_instructions_sent] == true
      session.delete(:password_reset_instructions_sent)
      @password_reset_instructions_sent = true
    end

    if session[:password_successfully_reset] == true
      session.delete(:password_successfully_reset)
      @password_successfully_reset = true
    end

    return unless session[:invitation_link_invalid] == true

    session.delete(:invitation_link_invalid)
    @invitation_link_invalid = true
  end

  def handle_signin
    # Remove null bytes from credentials to prevent database/BCrypt errors
    credentials = params.permit(:email_address, :password)
    credentials[:email_address] = credentials[:email_address].to_s.delete("\0") if credentials[:email_address].present?
    credentials[:password] = credentials[:password].to_s.delete("\0") if credentials[:password].present?

    if (user = User.authenticate_by(credentials))

      # Make sure we have a person for this user
      if user.person.nil?
        person = Person.find_by(email: user.email_address)
        if person
          person.user = user
          person.save!
        else
          user.create_person(email: user.email_address, name: user.email_address.split("@").first)
        end
      end

      # Continue signing them in.
      start_new_session_for user

      # Redirect to the last dashboard they were on
      last_dashboard_prefs = cookies.encrypted[:last_dashboard]
      # Reset if it's an old string value instead of a hash
      last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
      user_preference = last_dashboard_prefs[user.id.to_s]
      default_path = case user_preference
      when "manage"
                       manage_path
      else
                       my_dashboard_path
      end

      redirect_to(session.delete(:return_to) || default_path) and return
    else
      @error = true
      render :signin, status: :unprocessable_entity
    end
  end

  def signout
    # Cookie [:last_dashboard] persists automatically across sign-outs
    terminate_session
    redirect_to root_path
  end

  def password
    return unless session[:reset_link_expired_or_invalid] == true

    session.delete(:reset_link_expired_or_invalid)
    @reset_link_expired_or_invalid = true
  end

  def handle_password
    # Remove null bytes and validate email format
    sanitized_email = params[:email_address].to_s.delete("\0").strip.downcase

    # Always show success message to prevent account enumeration
    # Only send email if user actually exists
    if sanitized_email.match?(URI::MailTo::EMAIL_REGEXP)
      user = User.find_by(email_address: sanitized_email)
      if user
        # Generate token using Rails 8's generates_token_for
        token = user.generate_token_for(:password_reset)
        AuthMailer.password(user, token).deliver_later
      end
    end

    # Always redirect with success message (even if user doesn't exist)
    session[:password_reset_instructions_sent] = true
    redirect_to signin_path and return
  end

  def reset
    # Use Rails 8's find_by_token_for which validates token and expiry
    @user = User.find_by_token_for(:password_reset, params[:token])
    if @user.nil?
      session[:reset_link_expired_or_invalid] = true
      redirect_to password_path and return
    end

    # Token is valid, render the reset password form
  end

  def handle_reset
    # Use Rails 8's find_by_token_for which validates token and expiry
    @user = User.find_by_token_for(:password_reset, params[:token])
    if @user.nil?
      session[:reset_link_expired_or_invalid] = true
      redirect_to password_path and return
    end

    # Remove null bytes from password to prevent BCrypt errors
    sanitized_password = params[:password].to_s.delete("\0")

    if @user.update(password: sanitized_password)
      session[:password_successfully_reset] = true
      redirect_to signin_path and return
    else
      @password_unsuccessfully_reset = true
      render :reset, status: :unprocessable_entity
    end
  end

  # DEPRECATED: This flow is replaced by PersonInvitation system
  # Keeping for backwards compatibility with any old invitation links
  def set_password
    @user = User.find_by(invitation_token: params[:token])
    if @user.nil? || !@user.invitation_token_valid?
      session[:invitation_link_invalid] = true
      redirect_to signin_path and return
    end

    # Get the production companies associated with this user's person
    @organizations = @user.person&.organizations || []
  end

  # DEPRECATED: This flow is replaced by PersonInvitation system
  # Keeping for backwards compatibility with any old invitation links
  def handle_set_password
    @user = User.find_by(invitation_token: params[:token])
    if @user.nil? || !@user.invitation_token_valid?
      session[:invitation_link_invalid] = true
      redirect_to signin_path and return
    end

    # Remove null bytes from password to prevent BCrypt errors
    sanitized_password = params[:password].to_s.delete("\0")

    if @user.update(password: sanitized_password, invitation_token: nil, invitation_sent_at: nil)
      # Automatically sign them in
      start_new_session_for @user
      redirect_to my_dashboard_path, notice: "Welcome to CocoScout! Your password has been set." and return
    else
      @password_unsuccessfully_set = true
      render :set_password
    end
  end

  private

  def user_params
    permitted_params = params.require(:user).permit(:email_address, :password)
    # Remove null bytes from email and password to prevent database/BCrypt errors
    if permitted_params[:email_address].present?
      permitted_params[:email_address] =
        permitted_params[:email_address].to_s.delete("\0")
    end
    permitted_params[:password] = permitted_params[:password].to_s.delete("\0") if permitted_params[:password].present?
    permitted_params
  end
end
