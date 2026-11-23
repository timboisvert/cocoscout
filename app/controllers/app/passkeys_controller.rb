# frozen_string_literal: true

module App
  # The apps make a passkey for the account they're signed in to (sign-in
  # plan phase 4): after a code or password sign-in ("Sign in with Face ID
  # next time"), and from the Account page's Add a passkey. JSON, from a
  # build that has its own sign-in screens, with the web view's cookies; the
  # system sheet (AuthenticationServices on the iPhone, Credential Manager on
  # Android) makes the key between the two calls.
  class PasskeysController < ApplicationController
    include PasskeyChallenges

    skip_forgery_protection
    skip_before_action :track_my_dashboard
    skip_before_action :show_my_sidebar
    before_action :require_app_request
    rate_limit to: 20, within: 10.minutes, name: "app_passkeys",
               with: -> { render json: { status: "error", error: "too_many", message: "Too many tries. Please wait a few minutes and try again." }, status: :too_many_requests }

    # GET /app/passkeys/options
    def options
      return refuse(:impersonating, "Sign-in methods can't be changed while acting as someone else.") if impersonating?

      render json: keep_passkey_challenge(:app_passkey_registration, SignIn::Passkeys.registration_options(Current.user, relying_party: passkey_relying_party))
    end

    # POST /app/passkeys { credential }
    def create
      return refuse(:impersonating, "Sign-in methods can't be changed while acting as someone else.") if impersonating?

      passkey = SignIn::Passkeys.register!(Current.user, params.require(:credential),
                                           challenge: take_passkey_challenge(:app_passkey_registration),
                                           relying_party: passkey_relying_party, user_agent: request.user_agent)
      render json: { status: "added", name: passkey.shown_name }
    rescue SignIn::Passkeys::Invalid, ActionController::ParameterMissing => e
      Rails.logger.warn("[passkeys] app passkey not added for user #{Current.user.id}: #{e.message}")
      refuse(:invalid, "That passkey couldn't be added. Please try again.")
    end

    private

    def require_app_request
      return if NativeAppVersion.native_sign_in?(request.user_agent) && (request.get? || request.content_mime_type&.json?)

      head :not_found
    end

    def refuse(error, message)
      render json: { status: "error", error: error.to_s, message: message }, status: :unprocessable_content
    end
  end
end
