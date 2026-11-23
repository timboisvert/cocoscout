# frozen_string_literal: true

module SignIn
  # Continue with Apple and Continue with Google on the website (sign-in plan
  # phase 2; Tim, 2026-11-22). SignIn::Resolve decides what each return means;
  # this only carries people to the provider and back, and shows the steps
  # Resolve names:
  #
  #   connect    their address has an account with a chosen password: enter
  #              it once, or use a code, and the provider signs them in after
  #   add_email  Apple's Hide My Email: the address organizations know them by
  #   code       a code to that address, proving it
  #   create     a new person: their name, prefilled from the provider
  #
  # Signed in, the same buttons on the Account page connect the provider to
  # the account they're in. Not while acting as someone else.
  #
  # Apple returns by a cross-site POST, which our Lax session cookie doesn't
  # ride on, so apple_callback only parks what came back for two minutes and
  # sends the browser to apple_return, a GET that has the session.
  class ProvidersController < ApplicationController
    include SignInCompletion

    allow_unauthenticated_access only: %i[start google_callback apple_callback apple_return apple_notifications continue handle_continue]
    skip_forgery_protection only: %i[apple_callback apple_notifications]
    skip_before_action :track_my_dashboard
    skip_before_action :show_my_sidebar
    rate_limit to: 30, within: 5.minutes, only: %i[start handle_continue], name: "sign_in_providers", with: lambda {
      redirect_to signin_path, alert: "Too many tries. Please wait a few minutes and try again."
    }

    FLOW_LASTS = 10.minutes
    PENDING_LASTS = 15.minutes
    APPLE_PARKED_FOR = 2.minutes

    # POST /auth/:provider
    def start
      provider = params[:provider].to_s
      connecting = authenticated?
      unless SignIn::Providers.shown(user: Current.user, cookies: cookies, user_agent: request.user_agent).include?(provider)
        return redirect_to(connecting ? account_path : signin_path)
      end
      if connecting && impersonating?
        return redirect_to(account_path, alert: "Sign-in methods can't be changed while acting as someone else.")
      end

      state = SecureRandom.urlsafe_base64(24)
      nonce = SecureRandom.urlsafe_base64(24)
      session[:provider_flow] = { "provider" => provider, "state" => state, "nonce" => nonce,
                                  "intent" => connecting ? "connect" : "sign_in", "at" => Time.current.to_i }
      redirect_to SignIn::OAuth.authorize_url(provider, redirect_uri: callback_url(provider), state: state, nonce: nonce),
                  allow_other_host: true
    end

    # GET /auth/google/callback
    def google_callback
      handle_return("google", code: params[:code], state: params[:state], error: params[:error])
    end

    # POST /auth/apple/callback (cross-site, no session)
    def apple_callback
      key = SecureRandom.urlsafe_base64(24)
      Rails.cache.write("sign_in/apple/#{key}", { "code" => params[:code], "state" => params[:state], "user" => params[:user], "error" => params[:error] }.compact,
                        expires_in: APPLE_PARKED_FOR)
      redirect_to apple_sign_in_return_path(k: key), status: :see_other
    end

    # GET /auth/apple/return
    def apple_return
      cache_key = "sign_in/apple/#{params[:k]}"
      parked = params[:k].present? ? Rails.cache.read(cache_key) : nil
      Rails.cache.delete(cache_key) if parked
      return redirect_to(signin_path, alert: "That sign-in didn't finish. Please try again.") unless parked

      handle_return("apple", code: parked["code"], state: parked["state"], error: parked["error"], apple_user: parked["user"])
    end

    # POST /auth/apple/notifications: Apple says someone stopped using Sign in
    # with Apple with us, or deleted their Apple account. Its connection goes
    # (nothing to revoke: Apple already has).
    def apple_notifications
      claims = SignIn::IdToken.verify("apple", params[:payload], subject: false,
                                                                  audiences: [ SignIn::Providers::APPLE_BUNDLE_ID, SignIn::Providers.apple_services_id ].compact)
      event = JSON.parse(claims["events"].to_s)
      if %w[consent-revoked account-delete].include?(event["type"]) && event["sub"].present?
        UserIdentity.where(provider: "apple", uid: event["sub"].to_s).find_each do |identity|
          identity.skip_revoke = true
          identity.destroy
        end
      end
      head :ok
    rescue SignIn::IdToken::Invalid, JSON::ParserError
      head :bad_request
    end

    # GET /auth/continue: the step SignIn::Resolve named.
    def continue
      return redirect_to(signin_path) unless (@pending = pending)

      show_pending
    end

    # POST /auth/continue
    def handle_continue
      return redirect_to(signin_path, alert: "That took a while, so please start again.") unless (@pending = pending)

      case params[:step]
      when "password" then connect_with_password
      when "send_code" then send_code(@pending["email"])
      when "code" then check_code
      when "email" then take_email
      when "other_address" then save_pending("step" => "add_email", "email" => nil, "confirmed" => false) && redirect_to(sign_in_provider_continue_path)
      when "create" then create_account
      else redirect_to sign_in_provider_continue_path
      end
    end

    # DELETE /auth/:provider (Account page)
    def disconnect
      return redirect_to(account_path, alert: "Sign-in methods can't be changed while acting as someone else.") if impersonating?

      identity = Current.user.user_identities.find_by(provider: params[:provider].to_s)
      identity&.destroy
      name = SignIn::Providers.name(params[:provider])
      redirect_to account_path, notice: "#{name} no longer signs you in. Your email code always works."
    end

    private

    # ---- the return from Apple or Google -----------------------------------

    def handle_return(provider, code:, state:, error:, apple_user: nil)
      name = SignIn::Providers.name(provider)
      flow = session.delete(:provider_flow)
      unless valid_flow?(flow, provider, state)
        return redirect_to(signin_path, alert: "That sign-in didn't finish. Please try again.")
      end
      back = flow["intent"] == "connect" ? account_path : signin_path
      return redirect_to(back, notice: "Signing in with #{name} was canceled.") if error.present? || code.blank?

      tokens = SignIn::OAuth.exchange(provider, code: code, redirect_uri: callback_url(provider))
      claims = SignIn::IdToken.verify(provider, tokens[:id_token], nonce: flow["nonce"])
      profile = SignIn::Resolve::Profile.from_claims(provider, claims, name: apple_name(apple_user), refresh_token: tokens[:refresh_token])
      return connect_signed_in(profile) if flow["intent"] == "connect"

      result = SignIn::Resolve.call(profile)
      case result.kind
      when :known, :connected then finish_sign_in(result.user, method: provider)
      when :needs_proof then begin_pending(profile, "step" => "connect", "email" => result.user.email_address)
      when :needs_email then begin_pending(profile, "step" => "add_email")
      when :new_account then begin_pending(profile, "step" => "create", "email" => profile.usable_email, "confirmed" => true)
      end
    rescue SignIn::OAuth::Error, SignIn::IdToken::Invalid => e
      Rails.logger.warn("[sign_in] #{provider} return failed: #{e.class}: #{e.message}")
      redirect_to signin_path, alert: "#{name} couldn't confirm that sign-in. Try again, or continue with your email address."
    end

    def valid_flow?(flow, provider, state)
      flow.is_a?(Hash) && flow["provider"] == provider && state.present? &&
        ActiveSupport::SecurityUtils.secure_compare(flow["state"].to_s, state.to_s) &&
        Time.zone.at(flow["at"].to_i) > FLOW_LASTS.ago
    end

    def connect_signed_in(profile)
      return redirect_to(signin_path) unless authenticated?
      return redirect_to(account_path, alert: "Sign-in methods can't be changed while acting as someone else.") if impersonating?

      SignIn::Connect.call(user: Current.user, profile: profile, proof: :signed_in)
      redirect_to account_path, notice: "#{SignIn::Providers.name(profile.provider)} now signs you in."
    rescue SignIn::Connect::Taken
      redirect_to account_path, alert: "That #{SignIn::Providers.name(profile.provider)} account is already connected to a different CocoScout account."
    end

    # Apple sends the name once, on the first sign-in, beside the token.
    def apple_name(raw)
      data = raw.is_a?(String) ? JSON.parse(raw) : raw.to_h
      name = data["name"] || {}
      { "first_name" => name["firstName"], "last_name" => name["lastName"] }
    rescue JSON::ParserError
      {}
    end

    def callback_url(provider)
      base = Rails.env.production? ? "https://cocoscout.com" : request.base_url
      provider == "apple" ? "#{base}/auth/apple/callback" : "#{base}/auth/google/callback"
    end

    # ---- the steps -----------------------------------------------------------

    def begin_pending(profile, attributes)
      session[:provider_pending] = { "profile" => profile.to_session, "at" => Time.current.to_i }.merge(attributes)
      redirect_to sign_in_provider_continue_path
    end

    def pending
      data = session[:provider_pending]
      return nil unless data.is_a?(Hash) && Time.zone.at(data["at"].to_i) > PENDING_LASTS.ago

      data
    end

    def save_pending(changes)
      session[:provider_pending] = @pending.merge(changes)
      @pending = session[:provider_pending]
    end

    def profile = SignIn::Resolve::Profile.from_session(@pending["profile"])

    def show_pending(status: :ok)
      @profile = profile
      @provider_name = SignIn::Providers.name(@profile.provider)
      @step = @pending["step"]
      @email_address = @pending["email"]
      render :continue, status: status
    end

    def connect_with_password
      return redirect_to(sign_in_provider_continue_path) unless @pending["step"] == "connect"

      user = User.authenticate_by(email_address: @pending["email"].to_s, password: params[:password].to_s.delete("\0"))
      unless user
        @error = :password
        return show_pending(status: :unprocessable_content)
      end
      connect_and_finish(user, proof: :password)
    end

    def send_code(email)
      return redirect_to(sign_in_provider_continue_path) if email.blank?
      # A superadmin account always connects with its password, never a code.
      return redirect_to(sign_in_provider_continue_path) if @pending["step"] == "connect" && User.find_by(email_address: email)&.superadmin?

      result = SignIn::Code.deliver(email: email, purpose: "connect", user: User.find_by(email_address: email), ip_address: request.remote_ip)
      save_pending("step" => "code", "email" => email, "sent" => result.to_s)
      redirect_to sign_in_provider_continue_path
    end

    def check_code
      return redirect_to(sign_in_provider_continue_path) unless @pending["step"] == "code"

      status, = SignIn::Code.redeem(email: @pending["email"].to_s, purpose: "connect", code: params[:code])
      unless status == :ok
        @code_problem = status
        return show_pending(status: :unprocessable_content)
      end

      if (user = User.find_by(email_address: @pending["email"]))
        # A superadmin account connects only with its password.
        return save_pending("step" => "connect") && redirect_to(sign_in_provider_continue_path) if user.superadmin?

        connect_and_finish(user, proof: :code)
      else
        save_pending("step" => "create", "confirmed" => true)
        redirect_to sign_in_provider_continue_path
      end
    end

    def take_email
      return redirect_to(sign_in_provider_continue_path) unless @pending["step"] == "add_email"

      email = params[:email_address].to_s.delete("\0").strip.downcase
      unless email.match?(URI::MailTo::EMAIL_REGEXP) && !email.end_with?("@privaterelay.appleid.com")
        @error = :email
        @typed_email = email
        return show_pending(status: :unprocessable_content)
      end
      send_code(email)
    end

    def create_account
      email = @pending["email"].to_s
      return redirect_to(sign_in_provider_continue_path) unless @pending["step"] == "create" && @pending["confirmed"] && email.present?

      # Made in the meantime: their address is proven, so it connects.
      if (existing = User.find_by(email_address: email))
        return save_pending("step" => "connect") && redirect_to(sign_in_provider_continue_path) if existing.superadmin?

        return connect_and_finish(existing, proof: :code)
      end

      @first_name = params[:first_name].to_s.squish
      @last_name = params[:last_name].to_s.squish
      if @first_name.blank? || @last_name.blank?
        @error = :name
        return show_pending(status: :unprocessable_content)
      end

      result = AccountCreator.call(email: email, name: "#{@first_name} #{@last_name}", email_verified: true)
      user = result&.user
      unless user&.persisted?
        @error = :name
        return show_pending(status: :unprocessable_content)
      end

      SignIn::Connect.call(user: user, profile: profile, proof: :new_account)
      AuthMailer.signup(user).deliver_later
      session.delete(:provider_pending)
      start_new_session_for user, sign_in_method: profile.provider
      redirect_to post_authentication_landing_path(user, new_signup: true)
    rescue ActiveRecord::RecordInvalid, SignIn::Connect::Taken => e
      Rails.logger.warn("[sign_in] account not created from #{profile.provider}: #{e.class}")
      @error = :name
      show_pending(status: :unprocessable_content)
    end

    def connect_and_finish(user, proof:)
      SignIn::Connect.call(user: user, profile: profile, proof: proof)
      finish_sign_in(user, method: profile.provider)
    rescue SignIn::Connect::Taken
      session.delete(:provider_pending)
      redirect_to signin_path, alert: "That #{SignIn::Providers.name(profile.provider)} account is already connected to a different CocoScout account."
    end
  end
end
