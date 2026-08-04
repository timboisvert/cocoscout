# frozen_string_literal: true

# Funded money a payout run released back to the org — typically a payee who
# was paid another way after the run was funded. The money never leaves the
# org's Stripe balance; instead the credit automatically reduces the debit on
# the next run (see PayoutBatchService.fund!). Partially consumable, oldest
# first, so nothing is ever double-applied.
class PayoutFundingCredit < ApplicationRecord
  belongs_to :organization
  belongs_to :source, polymorphic: true, optional: true

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :consumed_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :available, -> { where("consumed_cents < amount_cents") }

  def remaining_cents
    amount_cents - consumed_cents
  end

  def self.available_cents(organization)
    where(organization: organization).available.sum(Arel.sql("amount_cents - consumed_cents"))
  end

  # Use up to `cents` of the org's credit (oldest first); returns how much was
  # actually consumed. Row-locked so two concurrent fund! calls can't both
  # spend the same credit.
  def self.consume!(organization, cents)
    used = 0
    transaction do
      where(organization: organization).available.order(:id).lock.each do |credit|
        break if used >= cents

        take = [ credit.remaining_cents, cents - used ].min
        credit.update!(consumed_cents: credit.consumed_cents + take)
        used += take
      end
    end
    used
  end
end
