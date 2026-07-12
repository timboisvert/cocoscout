# frozen_string_literal: true

# Builds and runs payout batches. Building gathers every payee with a positive
# balance who can receive Stripe payouts; running transfers each item to its
# connected account and posts the debiting ledger entries.
#
# Funding (org -> platform) is assumed handled before #process! (the batch's
# funding_status/PaymentIntent hooks are where an ACH/card debit would live).
class PayoutBatchService
  # Payee types that can hold a Stripe Connect account (groups/guests can't).
  PAYABLE_TYPES = %w[Person Contractor].freeze

  # Create a draft batch with one item per eligible payee (positive balance +
  # Connect-enabled). Returns the batch (with no items if nobody is payable).
  def self.build_for(organization:, created_by: nil, trigger: "manual")
    batch = PayoutBatch.create!(organization: organization, created_by: created_by, trigger: trigger, status: "draft")

    organization.payout_balances_by_payee.each do |(payee_type, payee_id), cents|
      next unless cents.positive? && PAYABLE_TYPES.include?(payee_type)

      payee = payee_type.constantize.find_by(id: payee_id)
      next unless payee&.can_receive_payouts?

      batch.items.create!(payee: payee, amount_cents: cents)
    end

    batch.recalculate_total!
    batch
  end

  FUNDING_METHODS = %w[ach card].freeze

  # Fund the batch from the org: an ACH debit (default, cheap, settles in a few
  # days) or a card charge (instant "pay now" rush). Creates a PaymentIntent
  # against the org's Stripe customer; card funding that succeeds immediately is
  # advanced straight into processing, while ACH waits for the webhook.
  def self.fund!(batch, method: nil, payment_method_id: nil)
    return batch if batch.total_cents.zero?

    org = batch.organization
    payment_method = payment_method_id.presence || org.funding_payment_method_id.presence
    raise Error, "Connect a bank or card to fund payouts first." if payment_method.blank?

    # The Stripe payment-method type: prefer the connected source's type, else
    # the caller's ach/card choice.
    pm_type = org.funding_payment_method_type.presence || (method == "card" ? "card" : "us_bank_account")

    intent = Stripe::PaymentIntent.create(
      amount: batch.total_cents,
      currency: "usd",
      customer: org.stripe_customer_id,
      payment_method: payment_method,
      payment_method_types: [ pm_type ],
      confirm: true,
      off_session: true,
      metadata: { payout_batch_id: batch.id }
    )
    batch.update!(status: "funding", funding_payment_intent_id: intent.id, funding_status: intent.status)
    advance_funding!(batch, intent.status)
    batch
  rescue Stripe::StripeError => e
    batch.update!(status: "failed", funding_status: "failed")
    raise Error, e.message
  end

  # Move a batch forward based on its funding PaymentIntent status. Called from
  # #fund! (instant card) and the payment_intent webhook (ACH settlement).
  def self.advance_funding!(batch, intent_status)
    case intent_status
    when "succeeded"
      batch.update!(status: "funded", funding_status: "succeeded")
      process!(batch)
    when "processing", "requires_action"
      batch.update!(funding_status: intent_status)
    end
    batch
  end

  class Error < StandardError; end

  # Transfer every pending item to its connected account. Each success posts a
  # `payout` ledger entry (debiting the balance); failures leave the balance intact.
  def self.process!(batch)
    batch.update!(status: "processing")

    batch.items.pending.find_each do |item|
      transfer = Stripe::Transfer.create(
        amount: item.amount_cents,
        currency: "usd",
        destination: item.payee.stripe_account_id,
        metadata: { payout_batch_item_id: item.id }
      )
      item.mark_paid!(transfer_id: transfer.id)
    rescue Stripe::StripeError => e
      item.mark_failed!(e.message)
    end

    all_paid = batch.items.where.not(status: "paid").none?
    batch.update!(status: all_paid ? "completed" : "failed", completed_at: Time.current)
    batch
  end
end
