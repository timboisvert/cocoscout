# frozen_string_literal: true

# One line of "what this payee is being paid for" inside a payout run. Rolls up
# into a PayoutBatchItem (the payee's total = one Stripe transfer). See
# CreatePayoutContributions for the model's shape.
class PayoutContribution < ApplicationRecord
  belongs_to :payout_batch
  belongs_to :payout_batch_item
  belongs_to :payee, polymorphic: true
  belongs_to :source, polymorphic: true, optional: true

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
      item.update_columns(amount_cents: item.payout_contributions.sum(:amount_cents), updated_at: Time.current)
    elsif item&.persisted?
      item.destroy
    end
    payout_batch.recalculate_total! if payout_batch&.persisted?
  end
end
