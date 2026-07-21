# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePayoutCalculator do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 4000) }

  it "counts revenue as the confirmed sum, and fee as what was actually charged" do
    # Sold three $40 seats, refunded two → $40 kept; the fee charged was $2.
    create(:course_registration, course_offering: offering, amount_cents: 4000, cocoscout_fee_cents: 200, status: "confirmed")
    create(:course_registration, course_offering: offering, amount_cents: 4000, cocoscout_fee_cents: 200, status: "refunded")
    create(:course_registration, course_offering: offering, amount_cents: 4000, cocoscout_fee_cents: 200, status: "refunded")

    payout = described_class.new(offering).calculate!
    expect(payout.total_revenue_cents).to eq(4000)  # not -4000
    expect(payout.platform_fee_cents).to eq(200)    # the fee actually charged, not a re-computed 10%
    expect(payout.net_revenue_cents).to eq(3800)    # $38 to the org
  end

  it "refresh_summary! updates a stale payout without touching line items" do
    reg = create(:course_registration, course_offering: offering, amount_cents: 4000, cocoscout_fee_cents: 200, status: "confirmed")
    payout = described_class.new(offering).calculate!
    manual = payout.line_items.create!(label: "John Smith", amount_cents: 1000)

    # Someone else registers later — the summary should catch up.
    create(:course_registration, course_offering: offering, amount_cents: 4000, cocoscout_fee_cents: 200, status: "confirmed")
    described_class.new(offering).refresh_summary!

    expect(payout.reload.total_revenue_cents).to eq(8000)
    expect(payout.net_revenue_cents).to eq(7600)
    expect(payout.line_items).to include(manual) # manual payment preserved
  end
end
