# frozen_string_literal: true

# The daily answer to "does what CocoScout says match Stripe?"
#
#   1. Stripe's balance (available + pending) equals the sum of every
#      imported balance line, so the import is complete.
#   2. Stripe's balance equals what we hold for theaters (Σ OrgCashEntry)
#      plus CocoScout's own money (Σ CocoScoutLedgerEntry) plus money on its
#      way in (a bank debit Stripe already shows that no ledger has taken
#      yet, see .in_transit). Anything left over is the difference, and it
#      should be zero.
#   3. Every Stripe line is tied to the record that caused it, with the
#      same amount (unmatched and mismatched lines are listed).
#   4. Every record of ours that moved money through Stripe more than a few
#      days ago has its Stripe line (missing ones are listed).
#   5. No Stripe webhook is sitting failed.
#
# One row per day (PlatformReconciliation); running again the same day
# replaces it.
class PlatformReconciliationCheck
  GRACE = 3.days
  LIST_LIMIT = 25

  def self.run!(now: Time.current)
    available, pending = stripe_balance
    stripe_cents = available && (available + pending)
    imported = StripeBalanceTransaction.where(currency: "usd").sum(:net_cents)
    held = OrgCashEntry.sum(:amount_cents)
    ours = CocoScoutLedgerEntry.sum(:amount_cents)
    transit = in_transit
    transit_cents = transit.sum { |row| row["cents"] }
    missing = missing_from_stripe(now)

    row = PlatformReconciliation.find_or_initialize_by(checked_on: now.to_date)
    row.update!(
      checked_at: now,
      stripe_balance_cents: stripe_cents,
      imported_net_cents: imported,
      held_for_orgs_cents: held,
      cocoscout_cents: ours,
      difference_cents: stripe_cents && (stripe_cents - held - ours - transit_cents),
      unmatched_count: StripeBalanceTransaction.where(match_status: "unmatched").count,
      mismatch_count: StripeBalanceTransaction.where(match_status: "mismatch").count,
      failed_webhook_count: WebhookEvent.failed.count,
      details: {
        "stripe_available_cents" => available,
        "stripe_pending_cents" => pending,
        "import_complete" => stripe_cents.nil? || stripe_cents == imported,
        "in_transit_cents" => transit_cents,
        "in_transit" => transit,
        "missing_from_stripe" => missing,
        "missing_count" => missing.values.sum { |ids| ids.size },
        "oldest_unmatched_at" => StripeBalanceTransaction.where(match_status: "unmatched").minimum(:occurred_at)&.iso8601
      }
    )
    row
  end

  # [available, pending] in cents, USD; [nil, nil] when Stripe can't be asked.
  def self.stripe_balance
    balance = Stripe::Balance.retrieve
    sum = ->(list) { Array(list).select { |b| b.currency == "usd" }.sum(&:amount) }
    [ sum.call(balance.available), sum.call(balance.pending) ]
  rescue Stripe::StripeError => e
    Rails.logger.warn("[PlatformReconciliationCheck] Stripe balance unavailable: #{e.message}")
    [ nil, nil ]
  end

  # Money Stripe already shows coming in, that no ledger has taken because it
  # hasn't landed: a payout run waiting on its bank debit, a theater's top-up,
  # a bill being collected from a bank. A theater's balance is credited (and
  # a bill counted as CocoScout's) only once the money lands, since a bank
  # debit can still bounce; if it does, Stripe's failure line cancels the
  # charge and the record drops out of here.
  def self.in_transit
    lines = StripeBalanceTransaction.where(category: %w[run_funding top_up billing])
    waiting = {
      "PayoutBatch" => PayoutBatch.where(status: "funding"),
      "BalanceTopUp" => BalanceTopUp.where(status: "pending"),
      "BillingInvoice" => BillingInvoice.where(status: %w[draft open])
    }
    waiting.flat_map do |type, records|
      sums = lines.where(matched_type: type, matched_id: records.select(:id)).group(:matched_id).sum(:amount_cents)
      found = type.constantize.where(id: sums.keys).includes(:organization).index_by(&:id)
      sums.filter_map do |id, cents|
        record = found[id]
        next if cents.zero? || record.nil?

        { "label" => in_transit_label(record), "organization" => record.organization&.name, "cents" => cents }
      end
    end
  end

  def self.in_transit_label(record)
    case record
    when PayoutBatch then "Payout run ##{record.id}: bank debit on its way"
    when BalanceTopUp then "Funds added from a theater's bank, on their way"
    when BillingInvoice then "#{record.label} bill #{record.number}: being collected"
    end
  end

  # Records that moved money through Stripe, older than the grace period and
  # newer than the start of the import, with no Stripe line matched to them.
  def self.missing_from_stripe(now)
    since = StripeBalanceTransaction.minimum(:occurred_at)
    return {} unless since

    window = since..(now - GRACE)
    matched = ->(type) { StripeBalanceTransaction.where(matched_type: type).select(:matched_id) }
    {
      "ticket_orders" => TicketOrder.where(money_path: "cocoscout", exchanged_from_id: nil, paid_at: window)
                                    .where.not(stripe_payment_intent_id: nil).where("total_cents > 0")
                                    .where.not(id: matched.call("TicketOrder")).limit(LIST_LIMIT).pluck(:id),
      "course_registrations" => CourseRegistration.where(paid_at: window).where.not(stripe_payment_intent_id: nil)
                                                  .where.not(id: matched.call("CourseRegistration")).limit(LIST_LIMIT).pluck(:id),
      "payee_transfers" => PayoutBatchItem.where(paid_at: window).where.not(stripe_transfer_id: nil)
                                          .where.not(id: matched.call("PayoutBatchItem")).limit(LIST_LIMIT).pluck(:id),
      "withdrawals" => BalanceWithdrawal.where(created_at: window).where(status: %w[sent paid bank_rejected])
                                        .where.not(id: matched.call("BalanceWithdrawal")).limit(LIST_LIMIT).pluck(:id)
    }.reject { |_, ids| ids.empty? }
  end

  # Superadmins hear about it when the check fails two days running, a
  # Stripe line has gone unexplained for more than GRACE, or a webhook failed.
  def self.alert?(row)
    return false if row.clean?

    yesterday = PlatformReconciliation.find_by(checked_on: row.checked_on - 1)
    oldest = row.details["oldest_unmatched_at"].presence && Time.zone.parse(row.details["oldest_unmatched_at"])
    (yesterday && !yesterday.clean?) || row.failed_webhook_count.positive? ||
      (oldest && oldest < row.checked_at - GRACE) || !row.details.fetch("import_complete", true)
  end

  private_class_method :stripe_balance, :missing_from_stripe, :in_transit_label
end
