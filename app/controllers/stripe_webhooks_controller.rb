# frozen_string_literal: true

class StripeWebhooksController < ApplicationController
  # Webhooks don't use CSRF or session auth
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access

  # POST /webhooks/stripe
  def create
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    endpoint_secret = ENV["STRIPE_WEBHOOK_SECRET"] || Rails.application.credentials.dig(:stripe, :webhook_secret)

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
    metadata = session.metadata
    course_offering_id = metadata["course_offering_id"]
    person_id = metadata["person_id"]

    # Only handle course registration checkout sessions
    return unless course_offering_id.present? && person_id.present?

    offering = CourseOffering.find_by(id: course_offering_id)
    return unless offering

    person = Person.find_by(id: person_id)
    return unless person

    # Idempotent: skip if already confirmed for this checkout session
    existing = CourseRegistration.find_by(stripe_checkout_session_id: session.id)
    return if existing&.confirmed?

    # Create the confirmed registration
    registration = offering.course_registrations.create!(
      person: person,
      user: User.find_by(id: metadata["user_id"]),
      status: :confirmed,
      amount_cents: metadata["amount_cents"].to_i,
      currency: metadata["currency"] || "usd",
      registered_at: Time.current,
      paid_at: Time.current,
      stripe_checkout_session_id: session.id,
      stripe_payment_intent_id: session.payment_intent,
      cocoscout_fee_cents: calculate_cocoscout_fee(offering, metadata["amount_cents"].to_i)
    )

    # Fetch actual Stripe fee from the charge's balance transaction
    record_stripe_fee(registration, session.payment_intent)

    # Release Redis spot hold
    CourseSpotHoldService.release(offering.id, person.id)

    # Add registrant to talent pool, send emails, etc.
    CourseRegistrationConfirmationJob.perform_later(registration.id)
  rescue ActiveRecord::RecordNotUnique
    # Success page beat us to it — that's fine, it's already confirmed
    Rails.logger.info "Course registration already created for session #{session.id}"
  end

  def handle_charge_refunded(charge)
    # Find registration by payment intent
    registration = CourseRegistration.find_by(stripe_payment_intent_id: charge.payment_intent)
    return unless registration
    return if registration.refunded? # Idempotent

    registration.refund!
  end

  def calculate_cocoscout_fee(offering, amount_cents)
    return 0 if offering.feature_credit_redemption.present?
    (amount_cents * 0.05).round
  end

  def record_stripe_fee(registration, payment_intent_id)
    return unless payment_intent_id.present?

    payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
    charge_id = payment_intent.latest_charge
    return unless charge_id

    charge = Stripe::Charge.retrieve(charge_id)
    balance_transaction_id = charge.balance_transaction
    return unless balance_transaction_id

    balance_transaction = Stripe::BalanceTransaction.retrieve(balance_transaction_id)
    registration.update!(stripe_fee_cents: balance_transaction.fee)
  rescue Stripe::StripeError => e
    Rails.logger.error "Failed to fetch Stripe fee for registration #{registration.id}: #{e.message}"
  end
end
