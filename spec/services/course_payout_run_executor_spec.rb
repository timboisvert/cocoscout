# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePayoutRunExecutor do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 4000) }

  def make_payable(record)
    record.update!(stripe_account_id: "acct_#{record.class.name.downcase}_#{record.id}", payouts_enabled: true)
    record
  end

  # A LEGACY course-kind run, built the way pre-fold code staged it. New code
  # stages course money on the performer run (see CoursePayoutRunService) —
  # this executor only still pays old course drafts that predate the fold.
  def build_run
    org.reload
    payout = offering.create_course_offering_payout!(
      status: "calculated", total_revenue_cents: 3800, platform_fee_cents: 0,
      net_revenue_cents: 3800, total_payout_cents: 1000
    )
    instructor = make_payable(create(:person))
    line = payout.line_items.create!(payee: instructor, amount_cents: 1000, label: instructor.name,
                                     calculation_details: { type: "instructor" })

    batch = org.payout_batches.create!(kind: "course", status: "draft", trigger: "manual")
    instructor_item = batch.items.create!(payee: instructor, amount_cents: 1000, status: "pending")
    batch.payout_contributions.create!(payout_batch_item: instructor_item, payee: instructor,
                                       source: line, amount_cents: 1000, label: "Course: #{offering.title}")
    org_item = batch.items.create!(payee: org, amount_cents: 2800, status: "pending")
    batch.payout_contributions.create!(payout_batch_item: org_item, payee: org,
                                       source: payout, amount_cents: 2800,
                                       label: "Course: #{offering.title} — organization's share")
    batch.recalculate_total!
    batch
  end

  before do
    make_payable(org)
    allow(Stripe::Transfer).to receive(:create) { |args| double(id: "tr_#{args[:destination]}") }
  end

  it "transfers each item from the platform balance and marks them paid" do
    batch = build_run

    result = described_class.pay!(batch)

    expect(result.paid).to eq(2) # instructor + org
    expect(batch.reload.status).to eq("completed")
    expect(batch.items.all?(&:paid?)).to be(true)
    expect(batch.items.map(&:stripe_transfer_id)).to all(be_present)
    expect(Stripe::Transfer).to have_received(:create).twice
  end

  it "stamps each transfer with the course it settles" do
    batch = build_run
    described_class.pay!(batch)

    expect(Stripe::Transfer).to have_received(:create)
      .with(hash_including(metadata: hash_including(course_offering_id: offering.id, kind: "course"))).at_least(:once)
  end

  it "records the organization's remittance as a paid OrgPayout" do
    batch = build_run

    expect { described_class.pay!(batch) }.to change { OrgPayout.paid.count }.by(1)
    op = OrgPayout.paid.last
    expect(op.organization).to eq(org)
    expect(op.amount_cents).to eq(2800) # net 3800 − instructor 1000
  end

  it "does not touch the performer payout ledger (course money isn't owed by the org)" do
    batch = build_run

    expect { described_class.pay!(batch) }.not_to change(PayoutLedgerEntry, :count)
  end

  it "keeps the run open and records the error when Stripe rejects a transfer, so it can be retried" do
    batch = build_run
    allow(Stripe::Transfer).to receive(:create).and_raise(Stripe::StripeError.new("no funds"))

    result = described_class.pay!(batch)

    expect(result.failed).to eq(2)
    expect(batch.reload.status).to eq("draft") # stays open for retry
    expect(batch.items.none?(&:paid?)).to be(true)
    expect(batch.items.map(&:error)).to all(be_present)
  end

  it "retries only what hasn't been sent on a second run" do
    batch = build_run
    # First attempt fails everything, run stays open.
    allow(Stripe::Transfer).to receive(:create).and_raise(Stripe::StripeError.new("no funds"))
    described_class.pay!(batch)

    # Second attempt succeeds.
    allow(Stripe::Transfer).to receive(:create) { |args| double(id: "tr_#{args[:destination]}") }
    result = described_class.pay!(batch)

    expect(result.paid).to eq(2)
    expect(batch.reload.status).to eq("completed")
    expect(batch.items.all?(&:paid?)).to be(true)
  end

  it "tells the instructors their money is on its way" do
    batch = build_run

    expect { described_class.pay!(batch) }
      .to have_enqueued_job(PayoutSentPayeeNotificationJob).with(batch.id)
  end

  describe "org cash enforcement" do
    before { allow(OrgCashEntry).to receive(:enforcement_enabled?).and_return(true) }

    def credit_org!(cents)
      OrgCashEntry.post!(organization: org, entry_type: "adjustment", amount_cents: cents)
    end

    it "refuses the whole run when the org's held balance doesn't cover it" do
      batch = build_run
      credit_org!(1000) # run needs 3800

      result = described_class.pay!(batch)

      expect(result.error).to include("doesn't cover this run")
      expect(result.paid).to eq(0)
      expect(batch.items.none?(&:paid?)).to be(true)
      expect(Stripe::Transfer).not_to have_received(:create)
      # Nothing was reserved either.
      expect(OrgCashEntry.balance_cents(org)).to eq(1000)
    end

    it "pays and debits the org's balance when covered" do
      batch = build_run
      credit_org!(4000)

      result = described_class.pay!(batch)

      expect(result.paid).to eq(2)
      expect(result.error).to be_nil
      expect(OrgCashEntry.balance_cents(org)).to eq(200) # 4000 − 3800 sent
    end

    it "releases the reservation when Stripe rejects a transfer" do
      batch = build_run
      credit_org!(4000)
      allow(Stripe::Transfer).to receive(:create).and_raise(Stripe::StripeError.new("no funds"))

      described_class.pay!(batch)

      expect(OrgCashEntry.balance_cents(org)).to eq(4000)
    end

    it "a successful retry doesn't double-debit" do
      batch = build_run
      credit_org!(4000)
      allow(Stripe::Transfer).to receive(:create).and_raise(Stripe::StripeError.new("no funds"))
      described_class.pay!(batch)

      allow(Stripe::Transfer).to receive(:create) { |args| double(id: "tr_#{args[:destination]}") }
      described_class.pay!(batch)

      expect(OrgCashEntry.balance_cents(org)).to eq(200)
    end

    it "never spends another org's held money" do
      batch = build_run
      other_org = create(:organization)
      OrgCashEntry.post!(organization: other_org, entry_type: "adjustment", amount_cents: 100_000)

      result = described_class.pay!(batch)

      expect(result.error).to be_present
      expect(OrgCashEntry.balance_cents(other_org)).to eq(100_000)
      expect(Stripe::Transfer).not_to have_received(:create)
    end
  end

  it "freshens a stale payday so the payee isn't quoted a deposit window in the past" do
    batch = build_run
    batch.update!(payday: 10.days.ago.to_date)

    described_class.pay!(batch)

    expect(batch.reload.payday).to eq(Date.current)
    expect(batch.expected_deposit_range.first).to be >= Date.current
  end
end
