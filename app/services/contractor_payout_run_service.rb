# frozen_string_literal: true

# Adds an outgoing contract payment to the organization's open "contractor"
# payout run — the same accumulate-then-pay rail as performers and staff. One
# PayoutBatchItem per contractor (their running total = one Stripe transfer),
# with a PayoutContribution per contract payment. Each contribution posts an
# `earning` ledger entry (so the contractor's balance reflects it); the item
# posts the single debiting `payout` entry when paid, netting to zero.
#
# Idempotent per contract payment (unique source). Only outgoing, pending,
# priced payments to a contractor with a connected bank are added.
class ContractorPayoutRunService
  Result = Struct.new(:batch, :added, :error, keyword_init: true)

  class << self
    def add_contract_payment!(contract_payment, added_by: nil)
      contractor = contract_payment.contract&.contractor
      return failure("This payment isn't linked to a contractor.") unless contractor
      return failure("Only outgoing payments (money you owe) can go in a payout run.") unless contract_payment.direction_outgoing?
      return failure("This payment is already settled.") unless contract_payment.status_pending?

      cents = (contract_payment.amount.to_d * 100).round
      return failure("Set an amount on this payment before paying it.") if cents <= 0
      unless contractor.respond_to?(:can_receive_payouts?) && contractor.can_receive_payouts?
        return failure("#{contractor.name} hasn't connected a bank yet — send them the setup link first.")
      end

      if (existing = PayoutContribution.find_by(source: contract_payment))
        return Result.new(batch: existing.payout_batch, added: false, error: "already_added")
      end

      batch = nil
      ActiveRecord::Base.transaction do
        organization = contractor.organization
        batch = PayoutBatch.open_for(organization, kind: "contractor", created_by: added_by)

        item = batch.items.find_by(payee: contractor) ||
               batch.items.create!(payee: contractor, amount_cents: cents, status: "pending")

        contribution = PayoutContribution.create!(
          payout_batch: batch, payout_batch_item: item, payee: contractor,
          source: contract_payment, amount_cents: cents,
          label: label_for(contract_payment), description: contractor.name
        )
        PayoutLedgerEntry.post!(
          organization: organization, payee: contractor, entry_type: "earning",
          amount_cents: cents, source: contribution,
          description: "Contract payment: #{label_for(contract_payment)}", occurred_at: Time.current
        )
        item.update!(amount_cents: item.payout_contributions.sum(:amount_cents))
        batch.recalculate_total!
      end

      Result.new(batch: batch, added: true)
    end

    private

    def failure(message)
      Result.new(added: false, error: message)
    end

    def label_for(payment)
      contract = payment.contract
      context = contract&.production_name.presence || contract&.contractor_name
      detail = payment.description.presence || "Contract payment"
      [ context, detail ].compact.join(" — ")
    end
  end
end
