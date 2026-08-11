# frozen_string_literal: true

# One-time (but idempotently re-runnable) backfill of the per-org cash ledger
# from history that predates OrgCashEntry. Replays each source record through
# the same posting paths the live code uses, so the unique index on
# (source, entry_type) makes the backfill and go-forward posting mutually
# idempotent — a webhook restating a row later just updates it in place.
#
# What it replays, per organization:
#   + confirmed/refunded Stripe-paid course registrations (net of fees)
#   − refunds of those registrations
#   + online-paid contract payments (net of Stripe's fee)
#   − every paid item on a course-kind payout run (instructor transfers, org
#     remittances, contract remittances)
#   − OrgPayouts recorded by hand in superadmin (settled outside Stripe)
#   + one opening_balance entry for funded-run residue: outstanding funding
#     credit plus money parked on funded runs waiting for payees' banks
#
# Funded-run history is otherwise NOT replayed transfer-by-transfer: each
# funded run was ledger-neutral (funding in = transfers out), so only its
# residue is still in the platform balance.
class OrgCashBackfill
  OrgRow = Struct.new(:organization, :course_net_cents, :refund_cents, :contract_cents,
                      :course_run_debits_cents, :offline_org_payout_cents, :opening_balance_cents,
                      keyword_init: true) do
    def total_cents
      course_net_cents - refund_cents + contract_cents - course_run_debits_cents -
        offline_org_payout_cents + opening_balance_cents
    end
  end

  Result = Struct.new(:rows, :stripe_balance_cents, keyword_init: true) do
    def total_cents
      rows.sum(&:total_cents)
    end
  end

  def self.run!(dry_run: true)
    rows = Organization.order(:id).filter_map do |org|
      row = compute_row(org)
      next if row.total_cents.zero? && [ row.course_net_cents, row.contract_cents,
                                         row.course_run_debits_cents ].all?(&:zero?)

      post_row!(org, row) unless dry_run
      row
    end

    Result.new(rows: rows, stripe_balance_cents: stripe_balance_cents)
  end

  def self.compute_row(org)
    registrations = backfillable_registrations(org)
    refunded = registrations.select(&:refunded?)

    OrgRow.new(
      organization: org,
      course_net_cents: registrations.sum { |r| [ r.org_net_cents, 0 ].max },
      refund_cents: refunded.sum { |r| [ r.org_net_cents, 0 ].max },
      contract_cents: backfillable_contract_payments(org).sum(&:remittable_cents),
      course_run_debits_cents: paid_course_run_items(org).sum(:amount_cents),
      offline_org_payout_cents: offline_org_payouts(org).sum(:amount_cents),
      opening_balance_cents: funded_run_residue_cents(org)
    )
  end

  def self.post_row!(org, row)
    backfillable_registrations(org).each(&:sync_org_cash_entries)

    backfillable_contract_payments(org).each do |payment|
      OrgCashEntry.post!(
        organization: org,
        entry_type: "contract_payment",
        amount_cents: payment.remittable_cents,
        source: payment,
        description: "Contract payment ##{payment.id} collected",
        occurred_at: payment.paid_date&.to_time || payment.updated_at
      )
    end

    paid_course_run_items(org).find_each do |item|
      OrgCashEntry.post!(
        organization: org,
        entry_type: "transfer",
        amount_cents: -item.amount_cents,
        source: item,
        description: "Course payout run ##{item.payout_batch_id} transfer",
        occurred_at: item.paid_at || item.updated_at
      )
    end

    offline_org_payouts(org).find_each do |payout|
      OrgCashEntry.post!(
        organization: org,
        entry_type: "adjustment",
        amount_cents: -payout.amount_cents,
        source: payout,
        description: "Org payout ##{payout.id} settled outside Stripe",
        occurred_at: payout.paid_at || payout.updated_at
      )
    end

    residue = funded_run_residue_cents(org)
    if residue.positive?
      OrgCashEntry.post!(
        organization: org,
        entry_type: "opening_balance",
        amount_cents: residue,
        source: org,
        description: "Funded-run residue at ledger start (funding credit + parked payouts)"
      )
    end
  end

  # Course money that entered the shared Stripe balance: confirmed or refunded
  # registrations that actually paid through Stripe. (Refunded ones post both
  # their credit and the matching refund debit — net zero, both halves visible.)
  def self.backfillable_registrations(org)
    CourseRegistration
      .where(status: %w[confirmed refunded])
      .where.not(stripe_payment_intent_id: nil)
      .joins(course_offering: :production)
      .where(productions: { organization_id: org.id })
      .includes(course_offering: { feature_credit_redemption: :feature_credit })
  end

  def self.backfillable_contract_payments(org)
    ContractPayment
      .where(status: "paid", payment_method: "online")
      .where.not(stripe_payment_intent_id: nil)
      .joins(:contract)
      .where(contracts: { organization_id: org.id })
  end

  def self.paid_course_run_items(org)
    PayoutBatchItem
      .joins(:payout_batch)
      .where(status: "paid",
             payout_batches: { organization_id: org.id, kind: "course" })
  end

  # Hand-recorded remittances (superadmin marked the org paid by check/cash/
  # zelle). Executor-created OrgPayouts never set paid_by_user — those rows are
  # the same money as their course-run item and must not double-debit.
  def self.offline_org_payouts(org)
    OrgPayout.where(organization: org, status: "paid").where.not(paid_by_user_id: nil)
  end

  # Money from funded (performer/staff) runs still sitting in the platform
  # balance: released-payee funding credit, plus items parked on funded runs
  # waiting on a payee's bank. The parked slice is immediately re-subtracted by
  # OrgCashEntry.committed_cents — in the balance, but spoken for.
  def self.funded_run_residue_cents(org)
    # to_i: summing a SQL expression (amount_cents - consumed_cents) comes back
    # as a BigDecimal, which only_integer validation rejects.
    PayoutFundingCredit.available_cents(org).to_i + OrgCashEntry.committed_cents(org).to_i
  end

  def self.stripe_balance_cents
    return nil if Stripe.api_key.blank?

    balance = Stripe::Balance.retrieve
    (balance.available + balance.pending).sum { |b| b.currency == "usd" ? b.amount : 0 }
  rescue Stripe::StripeError => e
    Rails.logger.warn("[OrgCashBackfill] couldn't read Stripe balance: #{e.message}")
    nil
  end
end
