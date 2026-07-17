# frozen_string_literal: true

# Public, no-login Stripe bank onboarding for a payee (Person or Contractor) we
# email a signed link to — guests, one-timers, and contractors who don't have a
# CocoScout account. Reached at /pay/setup/:token. The token resolves to the
# payee (see PayeeOnboardingToken); the rest mirrors My::PaymentsController's
# Stripe connect/return flow but without a session.
class PayeeOnboardingController < ApplicationController
  allow_unauthenticated_access
  before_action :set_payee

  # Landing page: shows who they are and whether they're already set up.
  def show; end

  # Kick off Stripe hosted onboarding (turbo:false on the button so the browser
  # follows the cross-origin redirect).
  def connect
    url = StripeConnectService.new(@payee).onboarding_link(
      return_url: payee_onboarding_return_url(token: @token),
      refresh_url: payee_onboarding_url(token: @token)
    )
    redirect_to url, allow_other_host: true
  rescue StripeConnectService::Error => e
    redirect_to payee_onboarding_path(token: @token), alert: "Couldn't start bank setup: #{e.message}"
  end

  # Stripe returns the payee here after onboarding — pull the latest account state.
  def return_from_stripe
    StripeConnectService.new(@payee).sync_account
    render :show
  rescue StripeConnectService::Error
    render :show
  end

  private

  def set_payee
    @token = params[:token]
    @payee = PayeeOnboardingToken.resolve(@token)
    render :invalid, status: :not_found unless @payee
  end
end
