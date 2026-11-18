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

  # Tips typed straight onto a payout run for this day, before the day had a
  # register to split (Tim, 2026-11-11: the week Settle up started, the run
  # already in flight carried that week's tips), count as paid: the share
  # waits only for any difference, so nobody is paid a day's tips twice.
  # Never more than the share itself: a hand-typed line is too loose a
  # record (one line often covered two nights, or went to one person where
  # the register splits three ways) to take money back from anyone on.
  before_save :count_tips_typed_on_a_run, if: -> { payout? && payout_contribution_id.nil? }

  # { person id => cents } typed as Tips for a date on the organization's
  # payout runs (any run not canceled or failed), by the date on each
  # worksheet line. Lines that came from a share are not typed.
  def self.typed_on_runs(organization, date)
    iso = date.iso8601
    from_shares = where.not(payout_contribution_id: nil).select(:payout_contribution_id)
    PayoutContribution.joins(:payout_batch)
                      .where(payout_batches: { organization_id: organization.id }).where.not(payout_batches: { status: %w[canceled failed] })
                      .where(label: "Tips", payee_type: "Person").where.not(id: from_shares)
                      .where("payout_contributions.worksheet @> ?", [ { date: iso } ].to_json)
                      .each_with_object(Hash.new(0)) do |line, sums|
      sums[line.payee_id] += line.worksheet_entries.select { |entry| entry["date"].to_s == iso }.sum { |entry| entry["amount_cents"].to_i }
    end
  end

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

  def count_tips_typed_on_a_run
    typed = self.class.typed_on_runs(settlement_day.organization, settlement_day.date)[person_id].to_i
    self.paid_cents = [ paid_cents.to_i, [ typed, amount_cents.to_i ].min ].max if typed.positive?
  end
  private :count_tips_typed_on_a_run

  def payout? = method == "payout"
  def cash? = method == "cash"
  def day_label = settlement_day.date.strftime("%b %-d")
end
