# frozen_string_literal: true

# One payee's line in a payout batch. When paid, it posts a negative `payout`
# ledger entry that debits the payee's company-wide balance.
class PayoutBatchItem < ApplicationRecord
  STATUSES = %w[pending paid failed].freeze

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
      update!(status: "paid", paid_at: Time.current, stripe_transfer_id: transfer_id || stripe_transfer_id)
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

    owed = [ organization.payout_balance_cents_for(payee, category: "performer"), 0 ].max
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
