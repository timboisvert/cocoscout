# frozen_string_literal: true

# Settles an incoming contract payment that was paid online, and queues the
# organization's remittance.
#
# The money is in CocoScout's balance (the contractor paid us, exactly like a
# course registration), so the org gets it through the fund-free "course" payout
# run — one Stripe transfer from the platform balance to the org's own Connect
# account. CocoScout keeps no margin: the org is remitted what arrived less what
# Stripe charged to process it.
#
# Idempotent. Both the webhook and the success page call this, and either may
# arrive first or twice.
class ContractPaymentCollection
  class << self
    # +session+ is a Stripe::Checkout::Session. Returns true when this call is
    # the one that settled the payment.
    def settle!(payment, session)
      intent_id = session.respond_to?(:payment_intent) ? session.payment_intent : nil

      settled = payment.with_lock do
        payment.mark_paid_online!(checkout_session_id: session.id, payment_intent_id: intent_id)
      end
      return false unless settled

      record_stripe_fee!(payment, intent_id)
      record_org_cash_credit!(payment)
      remit_to_organization!(payment)
      true
    rescue ActiveRecord::RecordNotUnique
      # Another caller settled this same checkout session first.
      false
    end

    # Queue every collected-but-unremitted payment for an org. The per-payment
    # remit is skipped when the org has no connected bank; nothing else ever
    # re-ran it, so that money sat invisible in the held balance forever. Called
    # when the org's Connect account comes alive (account.updated webhook) and
    # as an idempotent sweep from the payout screens.
    def remit_pending!(organization)
      return 0 unless organization.can_receive_payouts?

      payments = ContractPayment.direction_incoming.status_paid
                                .where.not(stripe_checkout_session_id: nil)
                                .joins(:contract)
                                .where(contracts: { organization_id: organization.id })
                                .where.missing(:payout_contribution)
                                .includes(:contract)
      payments.each { |payment| remit_to_organization!(payment) }
      payments.size
    end

    # Adds what the org is owed to its open course payout run. Skipped silently
    # when the org hasn't connected a bank — the money stays with CocoScout and
    # lands in the run as soon as they do (remit_pending! catches it up).
    def remit_to_organization!(payment)
      organization = payment.contract.organization
      cents = payment.remittable_cents
      return if cents.zero? || !organization.can_receive_payouts?

      ActiveRecord::Base.transaction do
        batch = PayoutBatch.open_for(organization, kind: "course")
        item = batch.items.find_by(payee: organization) ||
          batch.items.create!(payee: organization, amount_cents: cents, status: "pending")

        PayoutContribution.find_or_create_by!(source: payment) do |contribution|
          contribution.payout_batch = batch
          contribution.payout_batch_item = item
          contribution.payee = organization
          contribution.amount_cents = cents
          contribution.label = remittance_label(payment)
          contribution.description = organization.name
        end

        item.update!(amount_cents: item.payout_contributions.sum(:amount_cents))
        batch.recalculate_total!
      end
    end

    private

    # The collected money sits in CocoScout's shared Stripe balance until the
    # remittance run sends it — credit it to the org's cash ledger so it's
    # theirs (and only theirs) to pay out in the meantime.
    def record_org_cash_credit!(payment)
      OrgCashEntry.post!(
        organization: payment.contract.organization,
        entry_type: "contract_payment",
        amount_cents: payment.remittable_cents,
        source: payment,
        description: "Contract payment ##{payment.id} collected",
        occurred_at: Time.current
      )
    end

    def remittance_label(payment)
      contract = payment.contract
      subject = contract.production_name.presence || contract.contractor_name
      "Contract: #{subject} — #{payment.description.presence || 'payment'}"
    end

    # What Stripe took, read off the charge's balance transaction. Without it
    # we'd remit gross and CocoScout would eat the processing fee.
    def record_stripe_fee!(payment, intent_id)
      return if intent_id.blank?

      intent = Stripe::PaymentIntent.retrieve({ id: intent_id, expand: [ "latest_charge.balance_transaction" ] })
      fee = intent.latest_charge&.balance_transaction&.fee
      payment.update!(stripe_fee_cents: fee) if fee.present?
    rescue Stripe::StripeError => e
      # Remit gross rather than stall the payout; the fee is reconcilable later.
      Rails.logger.warn("Contract payment #{payment.id}: couldn't read Stripe fee — #{e.message}")
    end
  end
end
