# frozen_string_literal: true

module SignIn
  # Signing in with a passkey on the website (sign-in plan phase 4). The
  # email field on /signin offers the passkeys this browser or password
  # manager holds for cocoscout.com in its autofill (passkey_autofill
  # controller): options here, the browser signs, and the answer comes back
  # here, which starts the session like every other way in.
  class PasskeysController < ApplicationController
    include SignInCompletion
    include PasskeyChallenges

    allow_unauthenticated_access
    skip_before_action :track_my_dashboard
    skip_before_action :show_my_sidebar
    rate_limit to: 30, within: 5.minutes, name: "sign_in_passkeys",
               with: -> { render json: { status: "error", message: "Too many tries. Please wait a few minutes and try again." }, status: :too_many_requests }

    # GET /auth/passkey/options
    def options
      render json: keep_passkey_challenge(:passkey_sign_in, SignIn::Passkeys.authentication_options(relying_party: passkey_relying_party))
    end

    # POST /auth/passkey { credential }
    def create
      passkey = SignIn::Passkeys.authenticate(params.require(:credential), challenge: take_passkey_challenge(:passkey_sign_in),
                                                                           relying_party: passkey_relying_party)
      render json: { status: "signed_in", landing: open_session_for(passkey.user, method: "passkey") }
    rescue SignIn::Passkeys::Invalid, ActionController::ParameterMissing => e
      Rails.logger.warn("[passkeys] sign-in refused: #{e.message}")
      render json: { status: "error", message: "That passkey didn't work. Try again, or continue with your email address." }, status: :unprocessable_content
    end
  end
end
