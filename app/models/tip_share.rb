# frozen_string_literal: true

# One person's share of a day's tips (plan §9.3): paid on their next payout
# run (the one rail), or handed over in cash at close, out of door cash.
# With the organization's tip rule on (§9.14) a share is worked out from the
# span they worked, in the role they worked it, unless someone typed it.
class TipShare < ApplicationRecord
  METHODS = %w[payout cash].freeze
  SOURCES = %w[computed typed].freeze

  belongs_to :settlement_day
  belongs_to :person
  belongs_to :payout_contribution, optional: true
  belongs_to :house_role, optional: true

  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :method, inclusion: { in: METHODS }
  validates :source, inclusion: { in: SOURCES }

  # Shares from settled days that nobody has pulled onto a payout run yet:
  # what Pay People offers, the way it offers approved hours.
  def self.waiting_for(organization)
    joins(:settlement_day).where(settlement_days: { organization_id: organization.id, status: "settled" }, payout_contribution_id: nil)
                          .where("amount_cents > 0").includes(:settlement_day, :person).order("settlement_days.date")
  end

  def payout? = method == "payout"
  def cash? = method == "cash"
  def day_label = settlement_day.date.strftime("%b %-d")
end
