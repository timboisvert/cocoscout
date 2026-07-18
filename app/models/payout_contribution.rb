# frozen_string_literal: true

# One line of "what this payee is being paid for" inside a payout run. Rolls up
# into a PayoutBatchItem (the payee's total = one Stripe transfer). See
# CreatePayoutContributions for the model's shape.
class PayoutContribution < ApplicationRecord
  belongs_to :payout_batch
  belongs_to :payout_batch_item
  belongs_to :payee, polymorphic: true
  belongs_to :source, polymorphic: true, optional: true

  # Earning ledger entries a staff contribution posts (performer contributions
  # post none — their earning lives on the ShowPayoutLineItem). dependent:
  # :destroy so removing a contribution from an open run reverses what it owed.
  has_many :payout_ledger_entries, as: :source, dependent: :destroy

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :label, presence: true

  # If a contribution goes away (e.g. its show payout is recalculated and the
  # source line is deleted), re-sum the payee's item — and drop the item if it
  # has nothing left — then re-total the run.
  after_destroy :resettle_item_and_batch

  def amount_dollars
    amount_cents / 100.0
  end

  private

  def resettle_item_and_batch
    item = payout_batch_item
    if item&.payout_contributions&.exists?
      # Performer-scoped runs pay the net ledger balance; staff/legacy runs are
      # the sum of their contributions.
      if payout_batch&.kind == "performer"
        item.settle_performer_amount!
      else
        item.update_columns(amount_cents: item.payout_contributions.sum(:amount_cents), updated_at: Time.current)
      end
    elsif item&.persisted?
      item.destroy
    end
    payout_batch.recalculate_total! if payout_batch&.persisted?
  end
end
