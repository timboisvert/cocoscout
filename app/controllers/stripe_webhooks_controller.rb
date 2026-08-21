# frozen_string_literal: true

class StripeWebhooksController < ApplicationController
  # Webhooks don't use CSRF or session auth
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access

  # POST /webhooks/stripe
  def create
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    event = verified_event(payload, sig_header)
    return head :bad_request unless event

    # Stripe redelivers on any non-2xx, and money-moving handlers must not run
    # twice for the same event. First writer wins; everyone else no-ops.
    return head :ok unless WebhookEvent.claim!(provider: "stripe", event_id: event.id, event_type: event.type)

    case event.type
    when "checkout.session.completed"
      handle_checkout_completed(event.data.object)
    when "charge.refunded"
      handle_charge_refunded(event.data.object)
    when "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"
      handle_subscription_event(event.data.object)
    when "invoice.paid", "invoice.payment_failed"
      handle_invoice_event(event.data.object)
    when "account.updated"
      handle_connect_account_updated(event.data.object)
    when "transfer.reversed"
      handle_transfer_reversed(event.data.object)
    when "payout.failed"
      handle_connect_payout_failed(event.data.object, event.account)
    when "payment_intent.succeeded", "payment_intent.payment_failed"
      handle_payout_funding(event.data.object, event.type)
    end

    head :ok
  end

  private

  # Connect platforms need TWO Stripe endpoints on this URL: one for events on
  # our own account (funding PaymentIntents, subscriptions, transfer reversals)
  # and one for events on connected accounts (a payee finishing onboarding, or
  # their bank rejecting a deposit). Stripe mints a separate signing secret per
  # endpoint, so we have to accept either.
  #
  # Try each configured secret; the first that verifies wins. A payload that
  # matches none is not from Stripe.
  def verified_event(payload, sig_header)
    webhook_secrets.each do |secret|
      return Stripe::Webhook.construct_event(payload, sig_header, secret)
    rescue Stripe::SignatureVerificationError
      next
    rescue JSON::ParserError
      return nil
    end
    nil
  end

  def webhook_secrets
    [
      ENV["STRIPE_WEBHOOK_SECRET"],
      ENV["STRIPE_CONNECT_WEBHOOK_SECRET"],
      Rails.application.credentials.dig(:stripe, :webhook_secret)
    ].compact_blank.uniq
  end

  # A payout batch's funding PaymentIntent settled (ACH) or failed. On success,
  # advance the batch into processing (transfers go out); on failure, mark it
  # failed. Guarded by funding_payment_intent_id so non-batch PIs are ignored.
  def handle_payout_funding(intent, event_type)
    batch = PayoutBatch.find_by(funding_payment_intent_id: intent.id)
    return unless batch

    if event_type == "payment_intent.succeeded"
      PayoutBatchService.advance_funding!(batch, "succeeded", funded_cents: intent.amount)
    else
      batch.update!(status: "failed", funding_status: "failed")
      # A bounced debit used to be silent — the run just sat there "failed"
      # while everyone assumed the money was moving.
      PayoutFundingFailedNotificationJob.perform_later(batch.id)
    end
  end

  # A Connect transfer was reversed — the money never reached the payee. Route
  # it through the same path as a bank return so the ledger, the sources and
  # the run's status all follow.
  def handle_transfer_reversed(transfer)
    item = PayoutBatchItem.find_by(stripe_transfer_id: transfer.id)
    return unless item&.paid?

    # A reversal puts the money back in OUR platform balance (unlike a bank
    # return, where it lands in the payee's Connect balance) — so the org's
    # cash ledger gets it back too.
    PayoutBatchService.return_item!(item, reason: "Transfer reversed", cash_returned: true)
  end

  # A payout from a payee's Stripe balance to their own bank failed — a closed
  # account, or details that don't match. This is the only signal we get for a
  # bank rejection; our transfer succeeded days earlier.
  #
  # Stripe reports the payee's account and an amount, not our item id, and one
  # Stripe payout can bundle several of our transfers. We act only when a single
  # unreturned paid item matches that amount exactly. Anything ambiguous is
  # reported rather than guessed at — a wrong guess corrupts the ledger.
  def handle_connect_payout_failed(payout, account_id)
    return unless account_id

    payee = StripeConnectService.payee_for_account(account_id)
    return unless payee

    candidates = PayoutBatchItem.where(payee: payee, status: "paid").order(paid_at: :desc).to_a
    matches = candidates.select { |i| i.amount_cents == payout.amount }

    if matches.one?
      PayoutBatchService.return_item!(matches.first, reason: failure_reason(payout))
    else
      Rails.logger.warn(
        "[stripe] payout.failed for account #{account_id} (#{payout.amount}c) matched " \
        "#{matches.size} paid items — not guessing; flagging the payee instead."
      )
      PayoutAccountProblemNotificationJob.perform_later(payee.class.name, payee.id, payout.amount, failure_reason(payout))
    end
  end

  def failure_reason(payout)
    [ payout.try(:failure_message), payout.try(:failure_code) ].compact.reject(&:blank?).first ||
      "The bank rejected the deposit"
  end

  # A payee's Connect Express account changed (finished onboarding, payouts
  # enabled/disabled, new requirements). Refresh our columns from the event.
  def handle_connect_account_updated(account)
    payee = StripeConnectService.payee_for_account(account.id)
    return unless payee

    StripeConnectService.new(payee).sync_account(account)

    # A worker's payout ability changed — re-evaluate their staff memberships.
    # Onboarding completes only when they've also acknowledged (see
    # refresh_onboarding_state!); a connected bank alone isn't enough.
    if payee.is_a?(Person)
      OrganizationStaffMember.where(person_id: payee.id).find_each(&:refresh_onboarding_state!)
    end

    # They can be paid now — so pay them. Money debited from the org has been
    # parked on a funded run waiting for exactly this. The daily sweep would
    # catch it tomorrow morning; this makes the usual case immediate.
    RetryParkedPayoutsJob.perform_later(payee: payee) if payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts?

    # An ORG connecting its bank may have contract money collected before it
    # could be remitted — queue it now that there's somewhere to send it.
    ContractPaymentCollection.remit_pending!(payee) if payee.is_a?(Organization) && payee.can_receive_payouts?
  rescue StripeConnectService::Error => e
    Rails.logger.warn("Connect account.updated sync failed for #{account.id}: #{e.message}")
  end

  # Sync an org's subscription state from a Stripe subscription object.
  # SubscriptionSyncService maps non-access statuses (canceled, etc.) back to the
  # free tier, so the deleted event is handled by the same path.
  def handle_subscription_event(subscription)
    organization = organization_for_subscription(subscription)
    return unless organization

    SubscriptionSyncService.new(organization, subscription).call
  end

  def handle_invoice_event(invoice)
    subscription_id = invoice["subscription"]
    return if subscription_id.blank?

    organization = Organization.find_by(stripe_subscription_id: subscription_id) ||
                   Organization.find_by(stripe_customer_id: invoice["customer"])
    return unless organization

    SubscriptionSyncService.from_id(organization, subscription_id)
  rescue Stripe::StripeError => e
    Rails.logger.error "Failed to sync subscription from invoice: #{e.message}"
  end

  def organization_for_subscription(subscription)
    metadata_org_id = subscription.respond_to?(:metadata) ? subscription.metadata["organization_id"] : nil

    Organization.find_by(id: metadata_org_id) ||
      Organization.find_by(stripe_subscription_id: subscription.id) ||
      Organization.find_by(stripe_customer_id: subscription.customer)
  end

  def handle_checkout_completed(session)
    metadata = session.metadata

    # A contractor paying us under a contract (see ContractPaymentCheckout).
    if metadata["contract_payment_id"].present?
      handle_contract_payment_completed(session, metadata)
      return
    end

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

  # Money owed to an organization under a contract, paid through the public pay
  # link. Settling also queues the org's remittance; it's idempotent, so this
  # racing the success page is fine.
  def handle_contract_payment_completed(session, metadata)
    payment = ContractPayment.find_by(id: metadata["contract_payment_id"])
    return unless payment

    ContractPaymentCollection.settle!(payment, session)
  end

  def handle_charge_refunded(charge)
    # Find registration by payment intent
    registration = CourseRegistration.find_by(stripe_payment_intent_id: charge.payment_intent)
    return unless registration
    return if registration.refunded? # Idempotent

    registration.refund!
  end

  def calculate_cocoscout_fee(offering, amount_cents)
    CourseRegistration.platform_fee_cents_for(offering, amount_cents)
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
