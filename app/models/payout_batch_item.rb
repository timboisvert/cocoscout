# frozen_string_literal: true

# One payee's line in a payout batch. When paid, it posts a negative `payout`
# ledger entry that debits the payee's company-wide balance.
class PayoutBatchItem < ApplicationRecord
  STATUSES = %w[pending paid failed].freeze

  belongs_to :payout_batch
  belongs_to :payee, polymorphic: true
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
        occurred_at: paid_at || Time.current
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
end
