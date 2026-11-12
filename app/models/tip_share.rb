# frozen_string_literal: true

# One person's share of a day's tips (plan §9.3): paid on their next payout
# run (the one rail), or handed over in cash at close, out of door cash.
# With the organization's tip rule on (§9.14) a share is worked out from the
# span they worked, in the role they worked it, unless someone typed it.
#
# A day reopened after its tips were paid (Tim, 2026-11-04: paid means the
# payout run was submitted): the share lets go of that run's line and
# remembers what it paid (paid_cents), so the split can change like any
# other. amount_cents is always what the day says the person gets; what is
# still owed is the difference. More owed waits on Pay People like any
# tips. Overpaid comes out of the person's next pay there.
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
  # what Pay People offers, the way it offers approved hours. A share paid
  # before its day was reopened waits only for what it's still owed.
  def self.waiting_for(organization)
    unsettled(organization).where("tip_shares.amount_cents > COALESCE(tip_shares.paid_cents, 0)")
  end

  # Paid more than the day now gives them: it comes out of their next pay.
  def self.overpaid_for(organization)
    unsettled(organization).where(method: "payout").where("tip_shares.amount_cents < COALESCE(tip_shares.paid_cents, 0)")
  end

  def self.unsettled(organization)
    joins(:settlement_day).where(settlement_days: { organization_id: organization.id, status: "settled" }, payout_contribution_id: nil)
                          .includes(:settlement_day, :person).order("settlement_days.date")
  end

  # What the day gives them beyond what a submitted run already paid:
  # positive is still owed, negative is overpaid.
  def owed_cents = amount_cents - paid_cents.to_i
  def paid_before? = paid_cents.to_i.positive?
  def overpaid? = owed_cents.negative?

  # Taken out of the split. Someone already paid stays on the day at
  # nothing, so what they were paid is still accounted for.
  def drop!
    return destroy! unless paid_before?

    update!(amount_cents: 0, worked_from: nil, worked_to: nil, house_role_id: nil, source: "computed")
  end

  # The day was reopened and this share's run was already submitted: the
  # money stays paid, and the share is free to change.
  def keep_paid!
    update!(paid_cents: amount_cents, payout_contribution: nil)
  end

  def payout? = method == "payout"
  def cash? = method == "cash"
  def day_label = settlement_day.date.strftime("%b %-d")
end
