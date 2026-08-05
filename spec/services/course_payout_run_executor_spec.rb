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

  def build_run
    org.reload
    payout = offering.create_course_offering_payout!(
      status: "calculated", total_revenue_cents: 3800, platform_fee_cents: 0,
      net_revenue_cents: 3800, total_payout_cents: 1000
    )
    instructor = make_payable(create(:person))
    payout.line_items.create!(payee: instructor, amount_cents: 1000, label: instructor.name,
                              calculation_details: { type: "instructor" })
    CoursePayoutRunService.add_to_run!(payout).batch
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

  it "freshens a stale payday so the payee isn't quoted a deposit window in the past" do
    batch = build_run
    batch.update!(payday: 10.days.ago.to_date)

    described_class.pay!(batch)

    expect(batch.reload.payday).to eq(Date.current)
    expect(batch.expected_deposit_range.first).to be >= Date.current
  end
end
