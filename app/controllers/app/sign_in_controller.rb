# frozen_string_literal: true

module App
  # The apps' own sign-in screens (sign-in plan phase 3; Tim, 2026-11-22).
  # The same steps as the website's /signin and the steps after Apple or
  # Google, answered with JSON for the native Welcome, Email, Password, Code,
  # Create your account, Connect once, and Add your email address screens.
  #
  # The app posts with its web view's cookies and user agent, and writes the
  # cookies that come back into the web view's store, so the session this
  # starts is the web view's own: signed in here is signed in there. No link
  # ever signs anyone in.
  #
  # Every answer is one of:
  #   { status: "step",   step:, email:, … }   show this screen next
  #   { status: "signed_in", landing: }        load this page in the web view
  #   { status: "error",  error:, message: }   stay, and show the message
  #
  # Steps: password, code, create, connect (a provider matched an account
  # with a chosen password: enter it once, or use a code), add_email (Apple's
  # Hide My Email). Which step is open rides in session[:app_sign_in].
  class SignInController < ApplicationController
    include SignInCompletion

    allow_unauthenticated_access
    skip_forgery_protection
    skip_before_action :track_my_dashboard
    skip_before_action :show_my_sidebar
    before_action :require_app_request

    rate_limit to: 20, within: 3.minutes, only: %i[identify password code connect add_email provider exchange],
               name: "app_sign_in", with: -> { refuse(:too_many, "Too many tries. Please wait a few minutes and try again.", :too_many_requests) }
    rate_limit to: 10, within: 10.minutes, only: :send_code, name: "app_sign_in_codes",
               with: -> { refuse(:too_many, "Too many codes requested. Please wait a few minutes and try again.", :too_many_requests) }

    CONFIRMED_ADDRESS_LASTS = 30.minutes
    FLOW_LASTS = 30.minutes
    CODE_PROBLEMS = {
      wrong: "That code doesn't match. Check the email and try again.",
      expired: "That code has expired or was already used. Send a new code.",
      locked: "That code has had too many tries. Send a new code."
    }.freeze

    # GET /app/sign_in/nonce: the nonce the app's Apple or Google sheet signs
    # into its ID token, so a token can't be replayed into another session,
    # and the website's Google client id, which Android's Credential Manager
    # names as the token's audience (kept out of the app's code).
    def nonce
      value = SecureRandom.urlsafe_base64(24)
      session[:app_sign_in_nonce] = value
      render json: { nonce: value, google_client_id: (SignIn::Providers.google_client_id if SignIn::Providers.configured?("google")) }.compact
    end

    # POST /app/sign_in/start_over
    def start_over
      session.delete(:app_sign_in)
      render json: { status: "step", step: "start" }
    end

    # POST /app/sign_in/identify { email, password? }
    # A password manager may fill both: a right one signs in at once.
    def identify
      email = clean_email(params[:email])
      return refuse(:email, "Enter a valid email address.") unless email.match?(URI::MailTo::EMAIL_REGEXP)

      if params[:password].present? && (user = User.authenticate_by(email_address: email, password: params[:password].to_s.delete("\0")))
        return signed_in(user, method: "password")
      end

      user = User.find_by(email_address: email)
      if user&.password_chosen?
        save_flow("mode" => "email", "email" => email, "step" => "password")
        step("password")
      else
        start_code(email: email, user: user, purpose: user ? "sign_in" : "confirm_address", mode: "email")
      end
    end

    # POST /app/sign_in/password { password }
    def password
      email = flow["email"]
      return lost unless flow["mode"] == "email" && email.present?

      if (user = User.authenticate_by(email_address: email, password: params[:password].to_s.delete("\0")))
        signed_in(user, method: "password")
      else
        refuse(:password, "That password doesn't match. Try again, or use a code instead.")
      end
    end

    # POST /app/sign_in/send_code: "Email me a code instead", "Send a new
    # code", and "Use a code" on Connect once.
    def send_code
      email = flow["email"]
      return lost if email.blank?

      user = User.find_by(email_address: email)
      if flow["mode"] == "provider"
        # A superadmin account always connects with its password, never a code.
        return refuse(:password_only, "This account connects with its password.") if user&.superadmin?

        start_code(email: email, user: user, purpose: "connect", mode: "provider")
      else
        start_code(email: email, user: user, purpose: user ? "sign_in" : "confirm_address", mode: "email")
      end
    end

    # POST /app/sign_in/code { code }
    def code
      return lost unless flow["step"] == "code" && flow["email"].present?

      status, = SignIn::Code.redeem(email: flow["email"], purpose: flow["purpose"], code: params[:code])
      return refuse(status, CODE_PROBLEMS.fetch(status, CODE_PROBLEMS[:wrong])) unless status == :ok

      user = User.find_by(email_address: flow["email"])
      if flow["mode"] == "provider"
        if user&.superadmin?
          save_flow(flow.merge("step" => "connect"))
          return step("connect")
        end
        return connect_and_sign_in(user, proof: :code) if user
      elsif user
        user.update_column(:email_verified_at, Time.current)
        return signed_in(user, method: "code")
      end

      save_flow(flow.merge("step" => "create", "confirmed_at" => Time.current.to_i))
      step("create")
    end

    # POST /app/sign_in/create { first_name, last_name }
    def create
      email = flow["email"].to_s
      return lost unless flow["step"] == "create" && email.present? && address_confirmed?

      if (existing = User.find_by(email_address: email))
        return flow["mode"] == "provider" ? connect_and_sign_in(existing, proof: :code) : signed_in(existing, method: "code")
      end

      first_name = params[:first_name].to_s.squish
      last_name = params[:last_name].to_s.squish
      return refuse(:name, "Enter your first and last name.") if first_name.blank? || last_name.blank?

      user = AccountCreator.call(email: email, name: "#{first_name} #{last_name}", email_verified: true)&.user
      return refuse(:name, "That name didn't work. Check it and try again.") unless user&.persisted?

      method = "code"
      if flow["mode"] == "provider"
        SignIn::Connect.call(user: user, profile: pending_profile, proof: :new_account)
        method = pending_profile.provider
      end
      AuthMailer.signup(user).deliver_later
      session.delete(:app_sign_in)
      start_new_session_for user, sign_in_method: method
      render json: { status: "signed_in", landing: absolute(post_authentication_landing_path(user, new_signup: true)) }
    rescue ActiveRecord::RecordInvalid, SignIn::Connect::Taken => e
      Rails.logger.warn("[app_sign_in] account not created: #{e.class}")
      refuse(:name, "That name didn't work. Check it and try again.")
    end

    # POST /app/sign_in/provider { provider, id_token, authorization_code?, first_name?, last_name? }
    # From the iPhone's own Sign in with Apple sheet, or Android's Credential
    # Manager for Google: an ID token carrying the nonce this session asked for.
    def provider
      provider = params[:provider].to_s
      return refuse(:provider, "That sign-in isn't available.") unless SignIn::Providers::LIST.include?(provider) && SignIn::Providers.configured?(provider)

      expected = session.delete(:app_sign_in_nonce)
      return refuse(:provider, "That sign-in took too long. Please try again.") if expected.blank?

      # Apple's sheet signs the nonce's SHA-256; Google's signs it as given.
      nonce = provider == "apple" ? Digest::SHA256.hexdigest(expected) : expected
      claims = SignIn::IdToken.verify(provider, params[:id_token], nonce: nonce)
      refresh_token = apple_refresh_token(params[:authorization_code]) if provider == "apple"
      profile = SignIn::Resolve::Profile.from_claims(
        provider, claims, name: { "first_name" => params[:first_name], "last_name" => params[:last_name] },
                          refresh_token: refresh_token, client_id: (SignIn::Providers::APPLE_BUNDLE_ID if provider == "apple")
      )
      resolve(profile)
    rescue SignIn::IdToken::Invalid => e
      Rails.logger.warn("[app_sign_in] #{provider} token refused: #{e.message}")
      refuse(:provider, "#{SignIn::Providers.name(provider)} couldn't confirm that sign-in. Try again, or continue with your email address.")
    end

    # POST /app/sign_in/exchange { code, secret }
    # Back from a browser tab (Google on the iPhone, Apple on Android):
    # SignIn::ProvidersController#hand_to_app parked who the provider said
    # this is under the code; the secret proves this app started it.
    def exchange
      key = "sign_in/app_handoff/#{params[:code]}"
      parked = params[:code].present? ? Rails.cache.read(key) : nil
      Rails.cache.delete(key) if parked
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(params[:secret].to_s), padding: false)
      unless parked && ActiveSupport::SecurityUtils.secure_compare(parked["challenge"].to_s, challenge)
        return refuse(:provider, "That sign-in didn't finish. Please try again.")
      end

      resolve(SignIn::Resolve::Profile.from_session(parked["profile"]))
    end

    # POST /app/sign_in/connect { password }: Connect once, by the account's password.
    def connect
      return lost unless flow["mode"] == "provider" && flow["step"] == "connect"

      user = User.authenticate_by(email_address: flow["email"].to_s, password: params[:password].to_s.delete("\0"))
      return refuse(:password, "That password doesn't match. Try again#{', or use a code instead' unless superadmin_flow?}.") unless user

      connect_and_sign_in(user, proof: :password)
    end

    # POST /app/sign_in/add_email { email }: Apple's Hide My Email.
    def add_email
      return lost unless flow["mode"] == "provider" && flow["step"] == "add_email"

      email = clean_email(params[:email])
      unless email.match?(URI::MailTo::EMAIL_REGEXP) && !email.end_with?("@privaterelay.appleid.com")
        return refuse(:email, "Enter the email address organizations know you by. A private Apple address can't be used for your account.")
      end

      save_flow(flow.merge("email" => email))
      start_code(email: email, user: User.find_by(email_address: email), purpose: "connect", mode: "provider")
    end

    private

    # Only the app's own screens: JSON, from a build that says it has them.
    def require_app_request
      return if NativeAppVersion.native_sign_in?(request.user_agent) && (request.get? || request.content_mime_type&.json?)

      head :not_found
    end

    def resolve(profile)
      result = SignIn::Resolve.call(profile)
      case result.kind
      when :known, :connected
        signed_in(result.user, method: profile.provider)
      when :needs_proof
        start_provider_flow(profile, "step" => "connect", "email" => result.user.email_address)
        step("connect", superadmin: result.user.superadmin?)
      when :needs_email
        start_provider_flow(profile, "step" => "add_email")
        step("add_email")
      when :new_account
        start_provider_flow(profile, "step" => "create", "email" => profile.usable_email, "confirmed_at" => Time.current.to_i)
        step("create")
      end
    end

    def start_provider_flow(profile, attributes)
      save_flow({ "mode" => "provider", "profile" => profile.to_session }.merge(attributes))
    end

    def pending_profile = SignIn::Resolve::Profile.from_session(flow["profile"])

    def superadmin_flow? = User.find_by(email_address: flow["email"].to_s)&.superadmin?

    def connect_and_sign_in(user, proof:)
      SignIn::Connect.call(user: user, profile: pending_profile, proof: proof)
      signed_in(user, method: pending_profile.provider)
    rescue SignIn::Connect::Taken
      session.delete(:app_sign_in)
      refuse(:taken, "That #{SignIn::Providers.name(pending_profile.provider)} account is already connected to a different CocoScout account.")
    end

    def start_code(email:, user:, purpose:, mode:)
      result = SignIn::Code.deliver(email: email, purpose: purpose, user: user, ip_address: request.remote_ip)
      save_flow(flow.slice("profile").merge("mode" => mode, "email" => email, "step" => "code", "purpose" => purpose, "sent" => result.to_s))
      step("code")
    end

    def apple_refresh_token(authorization_code)
      return nil if authorization_code.blank?

      SignIn::OAuth.exchange("apple", code: authorization_code, redirect_uri: nil, client_id: SignIn::Providers::APPLE_BUNDLE_ID)[:refresh_token]
    rescue SignIn::OAuth::Error => e
      # The sign-in stands without it; only revoking later needs it.
      Rails.logger.warn("[app_sign_in] Apple code exchange failed: #{e.message}")
      nil
    end

    def signed_in(user, method:)
      landing = open_session_for(user, method: method)
      render json: { status: "signed_in", landing: absolute(landing) }
    end

    # The screen to show next, with what it needs.
    def step(name, **extra)
      data = { status: "step", step: name, email: flow["email"] }
      if name == "code"
        data[:code_lifetime] = SignIn::Code.lifetime_in_words
        data[:notice] = { "too_soon" => "We sent a code to this address a moment ago, so use that one. It can take a minute to arrive.",
                          "too_many" => "We've sent this address several codes in the last hour. Use the newest one, or request another later." }[flow["sent"]]
      end
      if flow["mode"] == "provider" && flow["profile"]
        profile = pending_profile
        data.merge!(provider: SignIn::Providers.name(profile.provider), first_name: profile.first_name, last_name: profile.last_name)
      end
      render json: data.merge(extra).compact
    end

    def refuse(error, message, status = :unprocessable_content)
      render json: { status: "error", error: error.to_s, message: message }, status: status
    end

    # The step it was on has lapsed (or never started): back to the start.
    def lost
      session.delete(:app_sign_in)
      render json: { status: "step", step: "start", notice: "That took a while, so please start again." }
    end

    def flow
      data = session[:app_sign_in]
      return {} unless data.is_a?(Hash) && Time.zone.at(data["at"].to_i) > FLOW_LASTS.ago

      data
    end

    def save_flow(data)
      session[:app_sign_in] = data.merge("at" => Time.current.to_i)
    end

    def address_confirmed?
      confirmed_at = flow["confirmed_at"].to_i
      confirmed_at.positive? && Time.zone.at(confirmed_at) > CONFIRMED_ADDRESS_LASTS.ago
    end

    def clean_email(value)
      value.to_s.delete("\0").strip.downcase
    end

    def absolute(path)
      path.to_s.start_with?("http") ? path : "#{request.base_url}#{path}"
    end
  end
end
