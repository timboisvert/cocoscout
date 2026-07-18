# frozen_string_literal: true

# Issues an advance to a performer as a payout in the organization's open
# performer run — money paid ahead of earnings. The advance is a
# PayoutContribution on the payee's item; when the run funds, the item's payout
# drives the payee's ledger balance negative, and future show earnings net
# against it automatically (see PayoutBatchItem#settle_performer_amount!). No
# separate deduction step, no remaining_balance to drift — the ledger is the
# single source of truth.
class AdvancePayoutService
  Result = Struct.new(:advance, :batch, :error, keyword_init: true)

  def self.issue!(person:, amount_cents:, production:, issued_by:, show: nil)
    amount_cents = amount_cents.to_i
    return Result.new(error: "Enter an advance amount greater than zero.") if amount_cents <= 0
    return Result.new(error: "Pick who the advance is for.") unless person

    org = production.organization
    advance = nil
    batch = nil

    ActiveRecord::Base.transaction do
      advance = production.person_advances.create!(
        person: person, show: show,
        advance_type: show ? "show" : "general",
        original_amount: amount_cents / 100.0, remaining_balance: amount_cents / 100.0,
        status: "pending", issued_at: Time.current, issued_by: issued_by
      )

      batch = PayoutBatch.open_for(org, kind: "performer", created_by: issued_by)
      item = batch.items.find_by(payee: person) ||
             batch.items.create!(payee: person, amount_cents: amount_cents, status: "pending")

      PayoutContribution.create!(
        payout_batch: batch, payout_batch_item: item, payee: person,
        source: advance, amount_cents: amount_cents,
        label: advance_label(show), description: person.try(:name)
      )
      item.settle_performer_amount!
      batch.recalculate_total!
    end

    Result.new(advance: advance, batch: batch)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(error: e.message)
  end

  def self.advance_label(show)
    show ? "Advance — #{show.name_with_date}" : "Advance"
  end
end
