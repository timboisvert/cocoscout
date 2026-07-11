# frozen_string_literal: true

# Builds a staff pay run: the manager enters hours (and any bonus / reimbursement
# / tips) for each staff member, and this turns that into a PayoutBatch that pays
# everyone through Stripe Connect. Each line posts an `earning` ledger entry (so
# the worker's balance + history reflect it) and a batch item that pays it back
# down, netting to zero.
#
# Cash tips are recorded on the line for the record but are NOT routed through
# Stripe. Only staff with a connected, payout-ready bank are paid; the rest are
# reported back as skipped so the manager can nudge them to finish onboarding.
class StaffPayRunService
  FREE_PAYMENTS_PER_MONTH = 2
  EXTRA_PAYMENT_FEE_CENTS = 100

  Result = Struct.new(:batch, :skipped, keyword_init: true)

  # amount actually routed through Stripe (cash tips excluded).
  def self.payable_cents(rate_cents:, hours:, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0)
    worked = (rate_cents.to_i * hours.to_f / 1.0).round
    worked + bonus_cents.to_i + reimbursement_cents.to_i + tips_cents.to_i
  end

  # How many Stripe payments this payee has already been sent this calendar
  # month — used to apply the "2 free, then $1" per-staff fee.
  def self.payments_this_month(organization:, payee:, at: Time.current)
    PayoutBatchItem.paid
                   .joins(:payout_batch)
                   .where(payout_batches: { organization_id: organization.id })
                   .where(payee: payee)
                   .where(paid_at: at.beginning_of_month..at.end_of_month)
                   .count
  end

  # lines: array of hashes with keys :staff_member, :hours, :bonus_cents,
  # :reimbursement_cents, :tips_cents, :cash_tips_cents, :notes.
  def self.build(organization:, created_by:, lines:, payday: nil)
    batch = nil
    skipped = []

    ActiveRecord::Base.transaction do
      batch = organization.payout_batches.create!(
        trigger: "manual", status: "draft", kind: "staff_pay", created_by: created_by, payday: payday
      )

      fee_total = 0
      lines.each do |line|
        member = line[:staff_member]
        payee = member.person
        amount = payable_cents(
          rate_cents: member.hourly_rate_cents,
          hours: line[:hours],
          bonus_cents: line[:bonus_cents],
          reimbursement_cents: line[:reimbursement_cents],
          tips_cents: line[:tips_cents]
        )
        next if amount <= 0

        unless payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts?
          skipped << { member: member, amount_cents: amount }
          next
        end

        item = batch.items.create!(payee: payee, amount_cents: amount, status: "pending")
        PayoutLedgerEntry.post!(
          organization: organization, payee: payee, entry_type: "earning",
          amount_cents: amount, source: item, description: "Staff pay run", occurred_at: Time.current
        )

        fee_total += EXTRA_PAYMENT_FEE_CENTS if payments_this_month(organization: organization, payee: payee) >= FREE_PAYMENTS_PER_MONTH
      end

      batch.update!(extra_payment_fee_cents: fee_total)
      batch.recalculate_total!
    end

    MeterStaffFeeJob.perform_later(batch.id) if batch.extra_payment_fee_cents.to_i.positive?
    Result.new(batch: batch, skipped: skipped)
  end
end
