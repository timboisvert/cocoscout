# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePayoutRunService do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 4000) }

  # A payee (Person or Organization) that Stripe has cleared for payouts.
  def make_payable(record)
    record.update!(stripe_account_id: "acct_#{record.class.name.downcase}_#{record.id}", payouts_enabled: true)
    record
  end

  def build_payout(net_cents:, total_payout_cents: 0)
    offering.create_course_offering_payout!(
      status: "calculated",
      total_revenue_cents: net_cents,
      platform_fee_cents: 0,
      net_revenue_cents: net_cents,
      total_payout_cents: total_payout_cents
    )
  end

  it "adds a payable instructor and the org remainder into the open course run" do
    make_payable(org)
    instructor = make_payable(create(:person))
    payout = build_payout(net_cents: 3800, total_payout_cents: 1000)
    payout.line_items.create!(payee: instructor, amount_cents: 1000, label: instructor.name,
                              calculation_details: { type: "instructor" })

    result = described_class.add_to_run!(payout)

    expect(result.batch.kind).to eq("course")
    expect(result.added).to eq(2)
    expect(result.batch.items.find_by(payee: instructor).amount_cents).to eq(1000)
    expect(result.batch.items.find_by(payee: org).amount_cents).to eq(2800) # 3800 - 1000
    expect(result.batch.total_cents).to eq(3800)
  end

  it "skips an instructor with no connected bank but still pays the org" do
    make_payable(org)
    instructor = create(:person) # no Connect account
    payout = build_payout(net_cents: 3800, total_payout_cents: 1000)
    payout.line_items.create!(payee: instructor, amount_cents: 1000, label: instructor.name,
                              calculation_details: { type: "instructor" })

    result = described_class.add_to_run!(payout)

    expect(result.batch.items.find_by(payee: instructor)).to be_nil
    expect(result.batch.items.find_by(payee: org).amount_cents).to eq(2800)
    expect(result.skipped).to eq(1)
    expect(result.added).to eq(1)
  end

  it "is idempotent per source and restates a changed amount" do
    make_payable(org)
    payout = build_payout(net_cents: 3800, total_payout_cents: 0)

    described_class.add_to_run!(payout)
    # Instructor gets added later, shrinking the org's share.
    payout.update!(total_payout_cents: 1000)
    result = described_class.add_to_run!(payout)

    org_items = result.batch.items.where(payee: org)
    expect(org_items.count).to eq(1) # not duplicated
    expect(org_items.first.amount_cents).to eq(2800) # restated from 3800
  end
end
