# frozen_string_literal: true

# One payee's line in a payout batch. When paid, it posts a negative `payout`
# ledger entry that debits the payee's company-wide balance.
class PayoutBatchItem < ApplicationRecord
  # "failed": the transfer never happened (Stripe refused it). "returned": the
  # money did leave, reached the payee's Stripe balance, and their bank rejected
  # the deposit — so it came back. The distinction matters because a return has
  # a ledger entry to reverse and settled sources to un-settle; a failure never
  # got that far.
  STATUSES = %w[pending paid failed returned].freeze

  belongs_to :payout_batch
  belongs_to :payee, polymorphic: true
  # Detail lines that sum to this item's amount (what the payee is being paid for).
  has_many :payout_contributions, dependent: :destroy
  # The `payout` ledger entry this item posts (removed if the item is destroyed).
  has_many :payout_ledger_entries, as: :source, dependent: :destroy

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :paid, -> { where(status: "paid") }

  delegate :organization, to: :payout_batch

  def paid?
    status == "paid"
  end

  # Mark paid and post the debiting ledger entry (idempotent per item).
  def mark_paid!(transfer_id: nil)
    transaction do
      # error is cleared: an item that had been parked or had failed carries the
      # reason it didn't go out, and that line is still rendered in red under a
      # paid payee if we leave it behind.
      update!(status: "paid", paid_at: Time.current, error: nil, stripe_transfer_id: transfer_id || stripe_transfer_id)

      # Course runs distribute money CocoScout already holds (course revenue), not
      # money the org owes its people — so they don't touch the performer/staff
      # payout ledger. Posting one here would push the payee's performer balance
      # negative (a payout with no matching earning).
      next if payout_batch.kind == "course"

      PayoutLedgerEntry.post!(
        organization: organization,
        payee: payee,
        entry_type: "payout",
        amount_cents: -amount_cents,
        source: self,
        description: "Payout ##{payout_batch_id}",
        occurred_at: paid_at || Time.current,
        category: payout_batch.kind == "staff_pay" ? "staffing" : "performer"
      )
    end
  end

  # Mark failed and remove any ledger entry it posted (so the balance is restored).
  def mark_failed!(message)
    transaction do
      update!(status: "failed", error: message.to_s.truncate(500))
      PayoutLedgerEntry.unpost!(source: self, entry_type: "payout")
      # The transfer never happened, so give the reserved money back to the
      # org's cash ledger too (no-op when nothing was reserved).
      OrgCashEntry.unpost!(source: self, entry_type: "transfer")
    end
  end

  # Stripe refused the transfer for a reason that fixes itself — the payee's
  # account isn't cleared to receive one *yet*. Unwind exactly like a failure,
  # but leave the item pending rather than "failed": nothing is wrong with the
  # run, the money simply stays parked on it until the next automatic pass. The
  # status change also mints a fresh transfer idempotency key (see
  # PayoutBatchService#process!), so that pass really re-tries.
  def mark_parked!(message)
    transaction do
      update!(status: "pending", paid_at: nil, error: message.to_s.truncate(500))
      PayoutLedgerEntry.unpost!(source: self, entry_type: "payout")
      OrgCashEntry.unpost!(source: self, entry_type: "transfer")
    end
  end

  def returned?
    status == "returned"
  end

  # The payee's bank rejected the deposit and Stripe handed the money back.
  #
  # Unlike mark_failed!, this does NOT delete the payout ledger entry: the
  # payment genuinely happened and then came back, and erasing it would leave
  # no trace of either. It posts a matching `reversal` instead, which restores
  # the payee's balance while keeping both halves of the story on the ledger.
  def mark_returned!(reason:)
    transaction do
      update!(status: "returned", error: reason.to_s.truncate(500))

      # Course runs never posted a payout entry, so there's nothing to reverse.
      next if payout_batch.kind == "course"

      PayoutLedgerEntry.post!(
        organization: organization,
        payee: payee,
        entry_type: "reversal",
        amount_cents: amount_cents,
        source: self,
        description: "Payout returned by the bank",
        category: payout_batch.kind == "staff_pay" ? "staffing" : "performer"
      )
    end
  end

  # Set a performer-run item to what the payee is actually net-owed: their net
  # performer ledger balance (earnings minus advances/prior payouts, floored at
  # 0) plus any advances being issued in THIS run (money paid ahead of earnings,
  # not yet on the ledger). Destroys the item and returns nil when nothing is
  # owed (e.g. an outstanding advance still exceeds their earnings). Only for
  # performer-scoped runs; staff runs keep item = sum of contributions.
  def settle_performer_amount!
    # Never re-settle a paid item — the transfer already happened and its payout
    # ledger entry is history that must stand.
    return self if paid?

    net_owed = [ organization.payout_balance_cents_for(payee, category: "performer"), 0 ].max
    # Pay only for the earning lines actually in THIS run (show payouts + contract
    # payments), capped at what's still net-owed so advances and prior payouts
    # still reduce it. This is what makes "Remove from run" work: dropping a line
    # lowers what the run pays, instead of always settling the payee's whole
    # balance. (Removing the last line settles to 0 and drops the item.)
    in_run_earnings = payout_contributions.payable.where.not(source_type: "PersonAdvance").sum(:amount_cents)
    owed = [ net_owed, in_run_earnings ].min
    pending_advance_cents = payout_contributions.where(source_type: "PersonAdvance").sum(:amount_cents)
    total = owed + pending_advance_cents

    if total.positive?
      update!(amount_cents: total)
      self
    else
      destroy
      nil
    end
  end
end
