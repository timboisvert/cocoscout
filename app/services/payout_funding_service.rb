# frozen_string_literal: true

# Lets an organization connect the bank account (ACH) or card it will fund
# payout runs from. Uses a Stripe Checkout Session in `setup` mode to collect
# the payment method + mandate, attaches it to the org's Stripe customer as the
# default, and remembers it so PayoutBatchService#fund! can charge it
# off-session.
class PayoutFundingService
  class Error < StandardError; end

  def initialize(organization)
    @organization = organization
  end

  # Hosted Checkout URL to collect a funding source.
  def setup_session_url(success_url:, cancel_url:)
    ensure_customer!
    Stripe::Checkout::Session.create(
      mode: "setup",
      customer: @organization.stripe_customer_id,
      # Bank accounts (ACH) only — we don't fund payouts from cards.
      payment_method_types: %w[us_bank_account],
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: { organization_id: @organization.id, purpose: "payout_funding" }
    ).url
  rescue Stripe::StripeError => e
    raise Error, e.message
  end

  # After the org returns from Checkout, read the set-up payment method, make it
  # the customer's default, and store it for funding runs.
  def save_from_session!(session_id)
    session = Stripe::Checkout::Session.retrieve(id: session_id, expand: [ "setup_intent" ])
    pm_id = session.setup_intent&.payment_method
    raise Error, "No payment method was set up." if pm_id.blank?

    payment_method = Stripe::PaymentMethod.retrieve(pm_id)
    Stripe::Customer.update(@organization.stripe_customer_id, invoice_settings: { default_payment_method: pm_id })

    @organization.update!(
      funding_payment_method_id: pm_id,
      funding_payment_method_type: payment_method.type,
      funding_payment_method_label: label_for(payment_method)
    )
  rescue Stripe::StripeError => e
    raise Error, e.message
  end

  def remove!
    @organization.update!(
      funding_payment_method_id: nil,
      funding_payment_method_type: nil,
      funding_payment_method_label: nil
    )
  end

  private

  def ensure_customer!
    return if @organization.stripe_customer_id.present?

    customer = Stripe::Customer.create(name: @organization.name, metadata: { organization_id: @organization.id })
    @organization.update!(stripe_customer_id: customer.id)
  end

  def label_for(payment_method)
    case payment_method.type
    when "us_bank_account"
      bank = payment_method.us_bank_account
      "#{bank.bank_name.presence || 'Bank'} •••• #{bank.last4}"
    when "card"
      card = payment_method.card
      "#{card.brand.to_s.titleize} •••• #{card.last4}"
    else
      payment_method.type.to_s.titleize
    end
  end
end
