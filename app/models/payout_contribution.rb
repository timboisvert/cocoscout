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

  # Negative amounts are real: a contract service settled by payout deduction
  # is a negative line on the item, so the payee sees their gross share and
  # the deduction itemized (see ContractorPayoutRunService).
  validates :amount_cents, presence: true, numericality: { only_integer: true }
  validates :label, presence: true

  # Contributions that count toward the payee's transfer and ledger. Excludes
  # recorded-only lines like cash tips, which are kept for the record but never
  # paid (staff already took their split from the bar tip jar).
  scope :payable, -> { where(excluded_from_payout: false) }

  def worksheet_entries
    Array(worksheet)
  end

  # The work dates this line covers, as [oldest, newest] Dates — so a payee
  # sees "Tips · Jun 12 – Jul 3" instead of a bare "Tips". Tips/cash-tips use
  # their per-day worksheet; worked-hours lines use the time entries tied to
  # this run. Nil for undated lines (bonus, reimbursement, balance payouts).
  def covered_date_range
    worksheet_dates = worksheet_entries.filter_map do |w|
      Date.parse(w["date"].to_s)
    rescue Date::Error
      nil
    end
    return [ worksheet_dates.min, worksheet_dates.max ] if worksheet_dates.any?

    if label.to_s.start_with?("Worked hours") && payee_type == "Person"
      min, max = StaffTimeEntry.where(payout_batch_id: payout_batch_id, person_id: payee_id)
                               .pluck(Arel.sql("MIN(started_at)"), Arel.sql("MAX(started_at)")).first
      return [ min.to_date, max.to_date ] if min && max
    end

    nil
  end

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
    # Never touch a paid item — the money already moved and its ledger payout is
    # history. Only open (unpaid) items resettle or drop.
    if item.nil? || item.paid?
      # leave the paid item and its ledger entry untouched
    elsif item.payout_contributions.payable.exists?
      # Performer-scoped runs pay the net ledger balance; staff/legacy runs are
      # the sum of their contributions. Recorded-only lines (cash tips) never
      # count toward the item amount.
      if payout_batch&.kind == "performer"
        item.settle_performer_amount!
      else
        item.update_columns(amount_cents: item.payout_contributions.payable.sum(:amount_cents), updated_at: Time.current)
      end
    elsif item.persisted?
      item.destroy
    end
    payout_batch.recalculate_total! if payout_batch&.persisted?
  end
end
