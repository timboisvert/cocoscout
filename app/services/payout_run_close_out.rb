# frozen_string_literal: true

# Closing out a funded run that's paid except for people who haven't
# connected a bank (Tim, 2026-10-12: old runs sat open for months over one or
# two people). Those people move to the organization's one standing
# "Waiting on bank info" run and the old run closes as paid.
#
# No money moves and nothing is debited again: the old run's funding already
# put their money in CocoScout's Stripe balance, and the waiting run is funded
# too, so it stays reserved for them (OrgCashEntry.committed_cents counts
# unpaid items on funded runs) and the daily sweep and Pay remaining pay each
# of them the moment they connect a bank (RetryParkedPayoutsJob,
# PayoutBatchService.pay_remaining!).
#
# The paper trail: every moved line keeps the run it came from
# (payout_contributions.moved_from_batch_id, moved_at), the old run records
# when and by whom it was closed out, and a person's staff hours move with
# their pay. Someone already waiting keeps one line: what they're owed is
# added to it.
class PayoutRunCloseOut
  class Error < StandardError; end

  Result = Data.define(:waiting_run, :moved)

  # Unpaid people on a run who can't be paid until they connect a bank.
  def self.waiting_items(batch)
    batch.items.select do |item|
      PayoutBatch::RETRYABLE_ITEM_STATUSES.include?(item.status) &&
        !(item.payee.respond_to?(:can_receive_payouts?) && item.payee.can_receive_payouts?)
    end
  end

  # Funded, partly paid, and everyone still unpaid is waiting on a bank (pay
  # anyone who's ready first). Never a course run or the waiting run itself.
  def self.closable?(batch)
    return false unless batch.status == "partially_paid" && batch.funding_status == "succeeded"
    return false if batch.kind == "course" || batch.waiting_on_banks?

    unpaid = batch.items.reject(&:paid?)
    unpaid.any? && waiting_items(batch).size == unpaid.size
  end

  # The organization's standing waiting run, made the first time it's needed.
  def self.waiting_run_for(organization, created_by: nil)
    organization.payout_batches.find_by(waiting_on_banks: true, status: "partially_paid") ||
      organization.payout_batches.create!(kind: "payout", status: "partially_paid", funding_status: "succeeded",
                                          trigger: "manual", waiting_on_banks: true, payday: Date.current,
                                          created_by: created_by)
  end

  def self.close!(batch, by: nil)
    moved = []
    waiting_run = nil
    batch.with_lock do
      raise Error, "Only a funded run whose unpaid people are all waiting on a bank can be closed out." unless closable?(batch)

      waiting_run = waiting_run_for(batch.organization, created_by: by)
      now = Time.current
      waiting_items(batch).each do |item|
        target = waiting_run.items.find_by(payee_type: item.payee_type, payee_id: item.payee_id,
                                           status: PayoutBatch::RETRYABLE_ITEM_STATUSES)
        item.payout_contributions.update_all(payout_batch_id: waiting_run.id, payout_batch_item_id: (target || item).id,
                                             moved_from_batch_id: batch.id, moved_at: now, updated_at: now)
        if item.payee_type == "Person"
          batch.staff_time_entries.where(person_id: item.payee_id).update_all(payout_batch_id: waiting_run.id, updated_at: now)
        end
        if target
          target.update!(amount_cents: target.amount_cents + item.amount_cents)
          # Its lines now belong to the existing one; nothing else hangs off a
          # pending item (its payout ledger entry posts only when paid).
          PayoutBatchItem.where(id: item.id).delete_all
        else
          item.update!(payout_batch_id: waiting_run.id, status: "pending", error: nil)
        end
        moved << { payee: item.payee, amount_cents: item.amount_cents }
      end

      waiting_run.recalculate_total!
      batch.recalculate_total!
      batch.update!(closed_out_at: now, closed_out_by: by)
      PayoutBatchService.finalize_status!(batch.reload)
    end
    Result.new(waiting_run: waiting_run, moved: moved)
  end
end
