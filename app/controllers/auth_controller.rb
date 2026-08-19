# frozen_string_literal: true

class AuthController < ApplicationController
  include SignupTracking

  allow_unauthenticated_access only: %i[signup handle_signup signin handle_signin password handle_password reset
                                        handle_reset]
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
    @signup_token = SignupFormToken.generate
  end

  def handle_signup
    return unless signup_gate_passed?

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

    # The user doesn't exist, so create the account (User + Person together)
    result = AccountCreator.call(email: user_params[:email_address], password: user_params[:password])
    @user = result.user

    if @user.persisted?
      start_new_session_for @user
      AuthMailer.signup(@user).deliver_later

      redirect_to post_authentication_landing_path(@user, new_signup: true) and return
    else
      @signup_token = SignupFormToken.generate
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
      redirect_to post_authentication_landing_path(Current.user) and return
    end

    @user = User.new

    if session[:password_reset_instructions_sent] == true
      session.delete(:password_reset_instructions_sent)
      @password_reset_instructions_sent = true
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
          user.people.create(email: user.email_address, name: user.email_address.split("@").first)
        end
      end

      # Continue signing them in.
      start_new_session_for user

      redirect_to post_authentication_landing_path(user) and return
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
      # This link is also how manager-created accounts get activated, so sign
      # them in directly instead of bouncing them to the signin form to type
      # the password they just chose.
      start_new_session_for @user
      redirect_to post_authentication_landing_path(@user),
                  notice: "Your password has been set — welcome back!" and return
    else
      @password_unsuccessfully_reset = true
      render :reset, status: :unprocessable_entity
    end
  end

  private

  # Bot defense for the public signup form, in front of everything else in
  # handle_signup. Two independent tells, either one refuses the signup:
  #
  #   * The honeypot: an off-screen text field ("website") no human sees.
  #     Scripts that fill every input fill it. Tripping it gets a quiet
  #     redirect home — no account, no error to learn from.
  #
  #   * The form token: SignupFormToken stamps the form with when it was
  #     served. A post arriving under MIN_AGE later, or with no valid token at
  #     all, is re-rendered as a 422 without creating anything. Too-fast keeps
  #     the same (still valid, now older) token so a real person just clicks
  #     again; missing/expired gets a fresh one.
  #
  # Added 2026-08-18 after a proxy-pool script created ~85 accounts in a day
  # with rotating decade-old user agents. Rack::Attack blocks that pool's
  # range outright; this is what stops the next one.
  def signup_gate_passed?
    if params[:website].present?
      Rails.logger.warn("[signup] honeypot tripped ip=#{request.remote_ip} ua=#{request.user_agent.to_s[0, 120]}")
      redirect_to root_path
      return false
    end

    age = SignupFormToken.age(params[:signup_token])
    return true if age && age >= SignupFormToken::MIN_AGE

    Rails.logger.warn("[signup] form token #{age ? "too young (#{age}s)" : 'missing/invalid'} ip=#{request.remote_ip}")
    @user = User.new(user_params)
    @signup_retry = true
    @signup_token = age ? params[:signup_token] : SignupFormToken.generate
    render :signup, status: :unprocessable_entity
    false
  end

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
