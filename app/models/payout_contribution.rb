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

  def amount_dollars
    amount_cents / 100.0
  end
end
