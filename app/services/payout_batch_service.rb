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
