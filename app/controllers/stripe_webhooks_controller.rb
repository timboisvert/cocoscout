# frozen_string_literal: true

class StripeWebhooksController < ApplicationController
  # Webhooks don't use CSRF or session auth
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access

  # POST /webhooks/stripe
  def create
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    endpoint_secret = Rails.application.credentials.dig(:stripe, :webhook_secret)

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError
      return head :bad_request
    rescue Stripe::SignatureVerificationError
      return head :bad_request
    end

    case event.type
    when "checkout.session.completed"
      handle_checkout_completed(event.data.object)
    when "charge.refunded"
      handle_charge_refunded(event.data.object)
    end

    head :ok
  end

  private

  def handle_checkout_completed(session)
    registration = CourseRegistration.find_by(stripe_checkout_session_id: session.id)
    return unless registration
    return if registration.confirmed? # Idempotent

    registration.confirm!(payment_intent_id: session.payment_intent)

    # Add registrant to the course production's talent pool
    CourseRegistrationConfirmationJob.perform_later(registration.id)
  end

  def handle_charge_refunded(charge)
    # Find registration by payment intent
    registration = CourseRegistration.find_by(stripe_payment_intent_id: charge.payment_intent)
    return unless registration
    return if registration.refunded? # Idempotent

    registration.refund!
  end
end
