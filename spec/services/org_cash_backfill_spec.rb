# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrgCashBackfill do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 4_000) }

  def stripe_registration(status: :confirmed, amount: 4_000, fee: 400)
    offering.course_registrations.create!(
      person: create(:person), status: status, amount_cents: amount, currency: "usd",
      registered_at: Time.current, paid_at: Time.current,
      refunded_at: status == :refunded ? Time.current : nil,
      stripe_checkout_session_id: "cs_#{SecureRandom.hex(4)}",
      stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}",
      cocoscout_fee_cents: fee
    )
  end

  before do
    # Creating history through the models posts live entries (the callbacks are
    # already wired) — wipe them so the backfill really rebuilds from nothing.
    stripe_registration
    stripe_registration(status: :refunded)

    # A free (non-Stripe) registration: no cash ever entered the balance.
    offering.course_registrations.create!(
      person: create(:person), status: :confirmed, amount_cents: 0, currency: "usd",
      registered_at: Time.current
    )

    # A paid course-run remittance of 1_000.
    course_batch = org.payout_batches.create!(kind: "course", status: "completed", trigger: "manual")
    course_batch.items.create!(payee: org, amount_cents: 1_000, status: "paid", paid_at: Time.current)

    # A superadmin hand-recorded payout (settled outside Stripe).
    OrgPayout.create!(organization: org, course_offering: offering, amount_cents: 500,
                      status: "paid", payout_type: "full_course", payment_method: "check",
                      paid_at: Time.current, paid_by_user: create(:user))

    # An executor-created OrgPayout (same money as its course-run item — must NOT double-debit).
    OrgPayout.create!(organization: org, course_offering: offering, amount_cents: 1_000,
                      status: "paid", payout_type: "full_course", payment_method: "bank_transfer",
                      paid_at: Time.current)

    # Funded-run residue: 700 of unconsumed funding credit + 300 parked on a funded run.
    PayoutFundingCredit.create!(organization: org, amount_cents: 700, note: "released payee")
    funded = org.payout_batches.create!(kind: "performer", status: "partially_paid",
                                        trigger: "manual", funding_status: "succeeded")
    funded.items.create!(payee: create(:person), amount_cents: 300, status: "pending")

    OrgCashEntry.delete_all
  end

  it "computes the org's balance components without writing in dry-run" do
    result = nil
    expect { result = described_class.run!(dry_run: true) }.not_to change(OrgCashEntry, :count)

    row = result.rows.find { |r| r.organization == org }
    expect(row.course_net_cents).to eq(7_200)      # two Stripe registrations at 3_600 net
    expect(row.refund_cents).to eq(3_600)          # one of them refunded
    expect(row.course_run_debits_cents).to eq(1_000)
    expect(row.offline_org_payout_cents).to eq(500)
    expect(row.opening_balance_cents).to eq(1_000) # 700 credit + 300 parked
    expect(row.total_cents).to eq(3_100)
  end

  it "posts entries that sum to the same total, idempotently" do
    described_class.run!(dry_run: false)
    expect(OrgCashEntry.balance_cents(org)).to eq(3_100)
    # The parked 300 is in the balance but committed to its funded run.
    expect(OrgCashEntry.available_cents(org)).to eq(2_800)

    expect { described_class.run!(dry_run: false) }.not_to change(OrgCashEntry, :count)
    expect(OrgCashEntry.balance_cents(org)).to eq(3_100)
  end

  it "shares its rows with the live posting paths (no double-count when a webhook restates)" do
    described_class.run!(dry_run: false)

    registration = offering.course_registrations.confirmed.where.not(stripe_payment_intent_id: nil).first
    registration.update!(stripe_fee_cents: 146) # the hourly fee backfill lands

    expect(OrgCashEntry.where(source: registration, entry_type: "course_registration").count).to eq(1)
  end

  it "ignores organizations with no money history" do
    quiet_org = create(:organization)
    result = described_class.run!(dry_run: true)
    expect(result.rows.map(&:organization)).not_to include(quiet_org)
  end
end
