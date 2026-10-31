# frozen_string_literal: true

# One person's share of a day's tips (plan §9.3): paid on their next payout
# run (the one rail), or handed over in cash at close, out of door cash.
class TipShare < ApplicationRecord
  METHODS = %w[payout cash].freeze

  belongs_to :settlement_day
  belongs_to :person
  belongs_to :payout_contribution, optional: true

  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :method, inclusion: { in: METHODS }

  def payout? = method == "payout"
  def cash? = method == "cash"
end
