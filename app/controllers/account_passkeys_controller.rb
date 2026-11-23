# frozen_string_literal: true

# Passkeys on the Account page (sign-in plan phase 4): adding one from this
# browser (passkey_add_controller.js asks for the options, has the browser
# make it, and sends it back), and removing one. Never while acting as
# someone else. The apps add theirs through App::PasskeysController.
class AccountPasskeysController < ApplicationController
  include PasskeyChallenges

  before_action :not_while_impersonating
  rate_limit to: 20, within: 10.minutes, only: %i[options create], name: "account_passkeys",
             with: -> { render json: { status: "error", message: "Too many tries. Please wait a few minutes and try again." }, status: :too_many_requests }

  # POST /account/passkeys/options
  def options
    render json: keep_passkey_challenge(:passkey_registration, SignIn::Passkeys.registration_options(Current.user, relying_party: passkey_relying_party))
  end

  # POST /account/passkeys { credential }
  def create
    passkey = SignIn::Passkeys.register!(Current.user, params.require(:credential),
                                         challenge: take_passkey_challenge(:passkey_registration),
                                         relying_party: passkey_relying_party, user_agent: request.user_agent)
    flash[:notice] = "Passkey added. Your face, fingerprint, or screen lock now signs you in."
    render json: { status: "added", name: passkey.shown_name }
  rescue SignIn::Passkeys::Invalid, ActionController::ParameterMissing => e
    Rails.logger.warn("[passkeys] not added for user #{Current.user.id}: #{e.message}")
    render json: { status: "error", message: "That passkey couldn't be added. Please try again." }, status: :unprocessable_content
  end

  # DELETE /account/passkeys/:id
  def destroy
    passkey = Current.user.passkeys.find(params[:id])
    passkey.destroy!
    redirect_to account_path, notice: "That passkey no longer signs you in. You can delete it from your password manager too."
  end

  private

  def not_while_impersonating
    return unless impersonating?

    message = "Sign-in methods can't be changed while acting as someone else."
    request.format.json? ? render(json: { status: "error", message: message }, status: :forbidden) : redirect_to(account_path, alert: message)
  end
end
