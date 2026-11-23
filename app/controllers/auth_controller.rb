# frozen_string_literal: true

# Signing in and creating an account are one screen that starts with the email
# address (the sign-in plan; Tim, 2026-11-22). Every step lives at exactly
# /signin: older app builds hide their top bar by exact path, so a step never
# gets a path of its own. Which step is showing rides in the session
# (session[:sign_in]), so a refresh keeps it.
#
#   start     the email address. What comes next depends on the account:
#   password  someone who chose a password enters it, or requests a code instead
#   code      a 6-digit code (SignIn::Code): for someone who never chose a
#             password, for a new address, or by choice
#   create    a new person, once the code has confirmed their address, enters
#             their name and the account opens (no password; AccountCreator)
#
# A right password always signs in, whichever step is showing. /signup,
# /password, and their posts stay for old links and pages and lead here (a
# signed-in person's /password leads to the Account page's password page).
# /reset/:token keeps working for links already in inboxes.
class AuthController < ApplicationController
  include SignupTracking
  include SignInCompletion

  STEPS = %w[start password code create].freeze
  # How long a confirmed address waits for its name before starting over.
  CONFIRMED_ADDRESS_LASTS = 30.minutes

  allow_unauthenticated_access only: %i[signup handle_signup signin handle_signin password handle_password reset
                                        handle_reset]
  rate_limit to: 20, within: 3.minutes, only: :handle_signin, name: "signin", with: lambda {
    redirect_to signin_path, alert: "Try again later"
  }
  rate_limit to: 5, within: 10.minutes, only: :handle_password, name: "password", with: lambda {
    redirect_to signin_path, alert: "Too many requests. Please try again later."
  }
  rate_limit to: 10, within: 10.minutes, only: :handle_signup, name: "signup", with: lambda {
    redirect_to signin_path, alert: "Too many signup attempts. Please try again later."
  }

  skip_before_action :track_my_dashboard
  skip_before_action :show_my_sidebar

  # /signup is the same screen now. SignupTracking has already taken ref,
  # intent, and plan from the address on the way in.
  def signup
    redirect_to signin_path(email_address: params[:email_address].presence)
  end

  # Old pages and the forms other pages embed (sign-up and audition entry,
  # course registration) post an email here. It starts the same steps.
  def handle_signup
    identify(clean_email(params.dig(:user, :email_address) || params[:email_address]))
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

    clear_sign_in_state if params[:start_over].present?
    # "Use your password instead", from the code step of someone with an account.
    if params[:use] == "password" && sign_in_state["purpose"] == "sign_in"
      self.sign_in_state = { "email" => sign_in_state["email"], "step" => "password" }
    end
    @email_address = clean_email(params[:email_address]).presence

    if session.delete(:reset_link_expired_or_invalid) == true
      @reset_link_expired_or_invalid = true
    end
    if session.delete(:invitation_link_invalid) == true
      @invitation_link_invalid = true
    end

    show_step
  end

  def handle_signin
    case params[:step]
    when "password"  then check_password
    when "send_code" then send_code
    when "code"      then check_code
    when "create"    then create_account
    else
      identify(clean_email(params[:email_address]), password: params[:password].to_s.delete("\0").presence,
                                                    typed_password: params[:step] != "start")
    end
  end

  def signout
    # Cookie [:last_dashboard] persists automatically across sign-outs
    terminate_session
    # The app goes back to its welcome screen, not the marketing site.
    redirect_to turbo_native_app? ? welcome_path : root_path
  end

  # Forgot it, or never chose one: both are the email-first screen now, where
  # a code gets either person in. Someone already signed in (an old link, or
  # an older app page) goes to the Account page's own password page.
  def password
    return redirect_to(choose_password_account_path) if authenticated?

    redirect_to signin_path(email_address: params[:email_address].presence)
  end

  # An old forgot-password page posting an email. Someone with an account is
  # sent a code; anyone else starts at the first screen.
  def handle_password
    return redirect_to(choose_password_account_path) if authenticated?

    email = clean_email(params[:email_address])
    user = User.find_by(email_address: email) if email.match?(URI::MailTo::EMAIL_REGEXP)
    return redirect_to(signin_path(email_address: email.presence)) unless user

    start_code(email: email, user: user, purpose: "sign_in")
  end

  def reset
    # Use Rails 8's find_by_token_for which validates token and expiry
    @user = User.find_by_token_for(:password_reset, params[:token])
    if @user.nil?
      session[:reset_link_expired_or_invalid] = true
      redirect_to signin_path and return
    end

    # Token is valid, render the reset password form
  end

  def handle_reset
    # Use Rails 8's find_by_token_for which validates token and expiry
    @user = User.find_by_token_for(:password_reset, params[:token])
    if @user.nil?
      session[:reset_link_expired_or_invalid] = true
      redirect_to signin_path and return
    end

    # Remove null bytes from password to prevent BCrypt errors
    sanitized_password = params[:password].to_s.delete("\0")

    if @user.update(password: sanitized_password)
      # The link came by email, so using it proves the address. This link is
      # also how manager-created accounts got activated, so sign them in
      # directly instead of bouncing them to the signin form.
      @user.update_column(:email_verified_at, Time.current)
      clear_sign_in_state
      start_new_session_for @user, sign_in_method: "reset_link"
      redirect_to post_authentication_landing_path(@user),
                  notice: "Your password has been set — welcome back!" and return
    else
      @password_unsuccessfully_reset = true
      render :reset, status: :unprocessable_content
    end
  end

  private

  # ---- the steps -----------------------------------------------------------

  # The first step: an email address came in. A password may have come with
  # it (a password manager filling both, or an older page that still shows
  # both fields), and a right one signs in at once.
  def identify(email, password: nil, typed_password: false)
    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      clear_sign_in_state
      @email_address = email.presence
      @email_error = true
      return show_step(status: :unprocessable_content)
    end

    if password && (user = User.authenticate_by(email_address: email, password: password))
      return complete_sign_in(user, method: "password")
    end

    user = User.find_by(email_address: email)
    if user && (user.password_chosen? || password)
      self.sign_in_state = { "email" => email, "step" => "password" }
      # Only say the password was wrong when the person typed one themselves.
      return redirect_to(signin_path) unless password && typed_password

      @error = true
      show_step(status: :unprocessable_content)
    elsif user
      start_code(email: email, user: user, purpose: "sign_in")
    else
      return unless signup_gate_passed?(email)

      start_code(email: email, user: nil, purpose: "confirm_address")
    end
  end

  def check_password
    email = sign_in_state["email"]
    return redirect_to(signin_path) if email.blank?

    password = params[:password].to_s.delete("\0")
    if (user = User.authenticate_by(email_address: email, password: password))
      complete_sign_in(user, method: "password")
    else
      self.sign_in_state = { "email" => email, "step" => "password" }
      @error = true
      show_step(status: :unprocessable_content)
    end
  end

  # "Email me a code instead" and "Send a new code".
  def send_code
    email = sign_in_state["email"]
    return redirect_to(signin_path) if email.blank?

    user = User.find_by(email_address: email)
    start_code(email: email, user: user, purpose: user ? "sign_in" : "confirm_address")
  end

  # Sends the code and moves to the code step. When a code can't go out (one
  # went moments ago, or the address has had its share for the hour) the step
  # still shows, saying so.
  def start_code(email:, user:, purpose:)
    result = SignIn::Code.deliver(email: email, purpose: purpose, user: user, ip_address: request.remote_ip)
    self.sign_in_state = { "email" => email, "step" => "code", "purpose" => purpose, "sent" => result.to_s }
    redirect_to signin_path
  end

  def check_code
    state = sign_in_state
    email = state["email"]
    return redirect_to(signin_path) if email.blank? || state["step"] != "code"

    status, _record = SignIn::Code.redeem(email: email, purpose: state["purpose"], code: params[:code])
    unless status == :ok
      @code_problem = status
      return show_step(status: :unprocessable_content)
    end

    if (user = User.find_by(email_address: email))
      user.update_column(:email_verified_at, Time.current)
      complete_sign_in(user, method: "code")
    else
      self.sign_in_state = { "email" => email, "step" => "create", "confirmed_at" => Time.current.to_i }
      redirect_to signin_path
    end
  end

  # A new person whose address the code just confirmed. Their name, and the
  # account opens: no password (they sign in with a code, and can choose a
  # password later on the Account page).
  def create_account
    state = sign_in_state
    email = state["email"]
    return redirect_to(signin_path) unless state["step"] == "create" && address_still_confirmed?(state)

    if (existing = User.find_by(email_address: email))
      return complete_sign_in(existing, method: "code")
    end

    @first_name = params[:first_name].to_s.squish
    @last_name = params[:last_name].to_s.squish
    if @first_name.blank? || @last_name.blank?
      @name_error = "Enter your first and last name."
      return show_step(status: :unprocessable_content)
    end

    result = begin
      AccountCreator.call(email: email, name: "#{@first_name} #{@last_name}", email_verified: true)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[signin] account not created for #{email}: #{e.message}")
      nil
    end
    unless result&.user&.persisted?
      @name_error = "That name didn't work. Check it and try again."
      return show_step(status: :unprocessable_content)
    end

    clear_sign_in_state
    start_new_session_for result.user, sign_in_method: "code"
    AuthMailer.signup(result.user).deliver_later
    redirect_to post_authentication_landing_path(result.user, new_signup: true)
  end

  # ---- shared pieces -------------------------------------------------------

  def complete_sign_in(user, method:)
    finish_sign_in(user, method: method)
  end

  # Sets what the view needs for the step in the session, and renders it.
  def show_step(status: :ok)
    state = sign_in_state
    @step = STEPS.include?(state["step"]) ? state["step"] : "start"
    @step = "start" if state["email"].blank?
    if @step == "create" && !address_still_confirmed?(state)
      clear_sign_in_state
      @step = "start"
    end
    @email_address = state["email"] unless @step == "start"
    @code_sent = state["sent"] if @step == "code"
    @code_purpose = state["purpose"] if @step == "code"
    @signup_token ||= SignupFormToken.generate if @step == "start"
    render :signin, status: status
  end

  def sign_in_state
    state = session[:sign_in]
    state.is_a?(Hash) ? state : {}
  end

  def sign_in_state=(state)
    session[:sign_in] = state
  end

  def clear_sign_in_state
    session.delete(:sign_in)
  end

  def address_still_confirmed?(state)
    confirmed_at = state["confirmed_at"].to_i
    confirmed_at.positive? && Time.zone.at(confirmed_at) > CONFIRMED_ADDRESS_LASTS.ago
  end

  # Remove null bytes to prevent database errors.
  def clean_email(value)
    value.to_s.delete("\0").strip.downcase
  end

  # Bot defense in front of the one thing a stranger's address can trigger: an
  # email to it, and then an account. Two independent tells, either one
  # refuses:
  #
  #   * The honeypot: an off-screen text field ("website") no human sees.
  #     Scripts that fill every input fill it. Tripping it gets a quiet
  #     redirect home — no account, no error to learn from.
  #
  #   * The form token: SignupFormToken stamps the form with when it was
  #     served. A post arriving under MIN_AGE later, or with no valid token at
  #     all, is re-rendered as a 422 without sending anything. Too-fast keeps
  #     the same (still valid, now older) token so a real person just clicks
  #     again; missing/expired gets a fresh one.
  #
  # Only an address with no account passes through here: someone signing in
  # is never slowed down.
  #
  # Added 2026-08-18 after a proxy-pool script created ~85 accounts in a day
  # with rotating decade-old user agents. Rack::Attack blocks that pool's
  # range outright; this is what stops the next one.
  def signup_gate_passed?(email)
    if params[:website].present?
      Rails.logger.warn("[signup] honeypot tripped ip=#{request.remote_ip} ua=#{request.user_agent.to_s[0, 120]}")
      redirect_to root_path
      return false
    end

    age = SignupFormToken.age(params[:signup_token])
    return true if age && age >= SignupFormToken::MIN_AGE

    Rails.logger.warn("[signup] form token #{age ? "too young (#{age}s)" : 'missing/invalid'} ip=#{request.remote_ip}")
    clear_sign_in_state
    @email_address = email
    @signup_retry = true
    @signup_token = age ? params[:signup_token] : SignupFormToken.generate
    show_step(status: :unprocessable_content)
    false
  end
end
