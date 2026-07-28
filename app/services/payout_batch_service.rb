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

  # Batch statuses that still "hold" money: an open draft (fund it from its own
  # run) or a run mid-flight. Money committed to one of these has posted its
  # earning to the ledger but not yet its offsetting payout, so a balance sweep
  # must NOT grab it again.
  UNSETTLED_BATCH_STATUSES = %w[draft funding funded processing].freeze

  # Create a draft batch with one item per eligible payee. The amount is the
  # payee's ledger balance MINUS anything already committed to another open/
  # in-flight run — so this balance sweep never double-pays money that's already
  # sitting in an open staff_pay/performer draft. Returns the batch (no items if
  # nobody has an un-committed positive balance).
  def self.build_for(organization:, created_by: nil, trigger: "manual")
    batch = PayoutBatch.create!(organization: organization, created_by: created_by, trigger: trigger, status: "draft")
    committed = committed_by_payee(organization, except_batch: batch)

    organization.payout_balances_by_payee.each do |(payee_type, payee_id), cents|
      next unless PAYABLE_TYPES.include?(payee_type)

      available = cents - committed[[payee_type, payee_id]].to_i
      next unless available.positive?

      payee = payee_type.constantize.find_by(id: payee_id)
      next unless payee&.can_receive_payouts?

      batch.items.create!(payee: payee, amount_cents: available)
    end

    batch.recalculate_total!
    batch
  end

  # Cents each payee already has staged in an open/in-flight run (pending items
  # only — a paid item already posted its payout to the ledger). Keyed by
  # [payee_type, payee_id] to match payout_balances_by_payee.
  def self.committed_by_payee(organization, except_batch: nil)
    scope = PayoutBatchItem
      .joins(:payout_batch)
      .where(payout_batches: { organization_id: organization.id, status: UNSETTLED_BATCH_STATUSES })
      .where(status: "pending")
    scope = scope.where.not(payout_batch_id: except_batch.id) if except_batch&.persisted?
    scope.group(:payee_type, :payee_id).sum(:amount_cents)
  end

  # Undo an unfunded draft run. Returns tied staff hours to the approved-unpaid
  # pool (dependent: :nullify clears payout_batch_id on destroy, but not paid_at),
  # then destroys the batch — cascading to its items, contributions, and the
  # earning ledger entries those posted. Draft-only: never touch money in flight.
  def self.discard!(batch)
    raise Error, "Only a draft run can be discarded." unless batch.status == "draft"

    ActiveRecord::Base.transaction do
      batch.staff_time_entries.update_all(paid_at: nil, updated_at: Time.current)
      batch.destroy!
    end
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
      settle_item_sources!(item, transfer.id)
      record_performer_activation!(batch, item)
    rescue Stripe::StripeError => e
      item.mark_failed!(e.message)
    end

    all_paid = batch.items.where.not(status: "paid").none?
    batch.update!(status: all_paid ? "completed" : "failed", completed_at: Time.current)
    batch
  end

  # Mark a paid performer a billable "active performer" for the payout's month —
  # this is the month Stripe bills us the active-account fee, so our $3 charge
  # lands in the same month. Only performer runs paying an individual Person;
  # staff are billed separately (StaffActivation, on scheduling). Best-effort:
  # a billing hiccup must never fail an already-completed payout.
  def self.record_performer_activation!(batch, item)
    return unless batch.kind == "performer" && item.payee.is_a?(Person)

    # Don't count a person paid *only* as a contractor (contract payments ride the
    # performer run too) toward the $3/active-performer charge — that's for
    # performing. A person with any show-payout contribution still counts.
    contributions = item.payout_contributions.to_a
    return if contributions.any? && contributions.all? { |c| c.source_type == "ContractPayment" }

    PerformerActivation.record!(
      organization: batch.organization, person: item.payee, month: item.paid_at || Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("Performer activation failed for payout item #{item.id}: #{e.message}")
  end

  # Flip each of a paid item's contribution sources to "paid" for traceability
  # (e.g. mark the ShowPayoutLineItems paid so the show reflects it). The item
  # itself already posted the ledger payout, so sources don't touch the ledger.
  def self.settle_item_sources!(item, transfer_id)
    item.payout_contributions.includes(:source).each do |contribution|
      source = contribution.source
      source.mark_paid_via_payout_run!(reference_id: transfer_id) if source.respond_to?(:mark_paid_via_payout_run!)
    end
  end
end
