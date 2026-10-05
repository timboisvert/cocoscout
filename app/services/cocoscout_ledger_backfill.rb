# frozen_string_literal: true

# Posts CocoScout's own ledger for everything that happened before it
# existed, from the same records that post it going forward. Idempotent.
# Dry run by default: posted inside a transaction, the check read, then
# rolled back.
class CocoScoutLedgerBackfill
  Result = Data.define(:counts, :by_type, :check, :dry_run)

  SOURCES = {
    "ticket orders" => -> { TicketOrder.where(money_path: "cocoscout", exchanged_from_id: nil).where.not(stripe_payment_intent_id: nil) },
    "ticket refunds" => -> { TicketRefund.where(status: "succeeded") },
    "course registrations" => -> { CourseRegistration.where.not(stripe_payment_intent_id: nil) },
    "contract payments" => -> { ContractPayment.where.not(stripe_checkout_session_id: nil) },
    "bills" => -> { BillingInvoice.all },
    "theaters paid by hand" => -> { OrgPayout.where(status: "paid").where.not(paid_by_user_id: nil) },
    "Stripe lines" => -> { StripeBalanceTransaction.all }
  }.freeze

  def self.run!(dry_run: true)
    result = nil
    ActiveRecord::Base.transaction do
      counts = SOURCES.transform_values do |scope|
        records = scope.call
        records.find_each { |record| CocoScoutLedgerPoster.post_for!(record) }
        records.count
      end
      by_type = CocoScoutLedgerEntry.group(:entry_type).sum(:amount_cents)
      check = PlatformReconciliationCheck.run!
      result = Result.new(counts: counts, by_type: by_type, check: check.attributes, dry_run: dry_run)
      raise ActiveRecord::Rollback if dry_run
    end
    result
  end

  # Whatever the records can't account for on the day CocoScout's ledger
  # starts, recorded once and labeled, so the check is exact from then on.
  def self.record_opening_difference!(row)
    return nil if row.difference_cents.to_i.zero?
    return nil if CocoScoutLedgerEntry.exists?(entry_type: "opening_difference")

    CocoScoutLedgerEntry.post!(source: row, entry_type: "opening_difference", amount_cents: row.difference_cents,
                               occurred_at: row.checked_at, description: "Opening difference as of #{row.checked_on.strftime('%b %-d, %Y')}")
  end
end
