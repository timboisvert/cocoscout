# frozen_string_literal: true

# Adds an outgoing contract payment to the organization's open *performer* payout
# run — contractors ride the same run as performers so the whole thing is funded
# by one ACH debit (no separate contractor run to fund). One PayoutBatchItem per
# contractor (their running total = one Stripe transfer), with a
# PayoutContribution per contract payment. Each contribution posts an `earning`
# ledger entry (so the contractor's balance reflects it); the item posts the
# single debiting `payout` entry when paid, netting to zero. Contractors don't
# trigger the $3/performer charge (that's gated to Person payees).
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

      # The payee is the contractor's explicitly-linked Person (the identity that
      # holds the Stripe account + ledger).
      payee = contractor.person
      return failure("Link a person to #{contractor.name} first, then they can connect a bank and be paid.") unless payee
      unless payee.can_receive_payouts?
        return failure("#{contractor.name} hasn't connected a bank yet — send them the setup link first.")
      end

      if (existing = PayoutContribution.find_by(source: contract_payment))
        return Result.new(batch: existing.payout_batch, added: false, error: "already_added")
      end

      batch = nil
      ActiveRecord::Base.transaction do
        organization = contractor.organization
        batch = PayoutBatch.open_for(organization, kind: "performer", created_by: added_by)

        item = batch.items.find_by(payee: payee) ||
               batch.items.create!(payee: payee, amount_cents: cents, status: "pending")

        contribution = PayoutContribution.create!(
          payout_batch: batch, payout_batch_item: item, payee: payee,
          source: contract_payment, amount_cents: cents,
          label: label_for(contract_payment), description: contractor.name
        )
        PayoutLedgerEntry.post!(
          organization: organization, payee: payee, entry_type: "earning",
          amount_cents: cents, source: contribution,
          description: "Contract payment: #{label_for(contract_payment)}", occurred_at: Time.current
        )
        # Services this contract agreed to settle out of the payout net here,
        # now that there's a share to net against.
        apply_service_deductions!(batch, item, contract_payment, contribution, payee, organization)

        # A full wash (deductions ate the whole share) may have removed the
        # contribution — and its item along with it — inside the netting.
        if PayoutBatchItem.exists?(item.id)
          item.reload.settle_performer_amount!
        end
        batch.recalculate_total!
      end

      Result.new(batch: batch, added: true)
    end

    # Net the contract's deduct-from-payout services against the share that just
    # joined this run. Per Tim's design: the deduction hits at settlement,
    # capped at the share — and any remainder a share can't cover stays a
    # payable incoming payment with its pay link, at the reduced amount.
    #
    # Two shapes:
    # - Deductions smaller than the share: each becomes a NEGATIVE contribution
    #   on the item (payee sees gross share + itemized deductions) plus a
    #   negative "adjustment" ledger entry so the net-owed math agrees.
    # - Deductions >= the share (a full wash): nothing rides the run at all.
    #   The share's contribution is reversed and BOTH sides settle explicitly —
    #   the outgoing share paid "by offset", the services paid by deduction —
    #   because leaving a zero-sum item would let settle_performer_amount!
    #   destroy the trail while the outgoing payment stayed pending and
    #   re-addable, silently costing the org the service fee.
    def apply_service_deductions!(batch, item, outgoing_payment, share_contribution, payee, organization)
      contract = outgoing_payment.contract
      return unless contract

      deductibles = contract.contract_payments
        .status_pending
        .direction_incoming
        .where(settlement_method: "payout_deduction", amount_tbd: false)
        .order(:due_date, :id)
        .reject { |p| PayoutContribution.exists?(source: p) }
        .select { |p| (p.amount.to_d * 100).round.positive? }
      return if deductibles.empty?

      share_cents = share_contribution.amount_cents
      total_owed = deductibles.sum { |p| (p.amount.to_d * 100).round }

      if total_owed >= share_cents
        settle_as_wash!(batch, outgoing_payment, share_contribution, deductibles, share_cents)
      else
        deduct_within_share!(batch, item, deductibles, payee, organization, contract)
      end
    end

    # The normal case: services cost less than the share, so they ride the run
    # as negative lines and the payee receives the difference.
    def deduct_within_share!(batch, item, deductibles, payee, organization, contract)
      deductibles.each do |payment|
        take = (payment.amount.to_d * 100).round
        contribution = PayoutContribution.create!(
          payout_batch: batch, payout_batch_item: item, payee: payee,
          source: payment, amount_cents: -take,
          label: "#{payment.description.presence || 'Service'} (deducted)",
          description: contract.contractor&.name
        )
        PayoutLedgerEntry.post!(
          organization: organization, payee: payee, entry_type: "adjustment",
          amount_cents: -take, source: contribution,
          description: "Deducted from payout: #{payment.description}", occurred_at: Time.current
        )
        payment.mark_paid_via_deduction!(reference: "payout_run_#{batch.id}")
      end
    end

    # The wash: services eat the whole share. No money moves — the share's
    # contribution (and its earning entry) reverses, the outgoing payment
    # settles as offset, and services settle by deduction up to the share.
    # Whatever the share couldn't cover stays payable directly.
    def settle_as_wash!(batch, outgoing_payment, share_contribution, deductibles, share_cents)
      # Destroying the contribution reverses its earning ledger entry and
      # re-settles (or drops) the item via its after_destroy.
      share_contribution.destroy!
      outgoing_payment.mark_paid!(method: "offset",
                                  reference: "offset against services (run ##{batch.id})")

      remaining = share_cents
      deductibles.each do |payment|
        break if remaining <= 0

        owed = (payment.amount.to_d * 100).round
        take = [ owed, remaining ].min
        if take >= owed
          payment.mark_paid_via_deduction!(reference: "offset_run_#{batch.id}")
        else
          # The rest is theirs to pay directly, at the reduced amount.
          remainder = (owed - take) / 100.0
          payment.update!(
            amount: remainder,
            settlement_method: "direct",
            description: "#{payment.description} (#{ActiveSupport::NumberHelper.number_to_currency(take / 100.0)} offset against payout)"
          )
        end
        remaining -= take
      end
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
