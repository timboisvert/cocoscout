# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePayoutCalculator, "standalone (no-contract) instructor split", type: :service do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 5000) }
  let(:instructor) { create(:person) }

  before do
    create(:course_registration, course_offering: offering, amount_cents: 5000, status: "confirmed")
    create(:course_registration, course_offering: offering, amount_cents: 5000, status: "confirmed")
  end

  it "pays a percentage-split instructor their share of net, to their Person" do
    offering.course_offering_instructors.create!(person: instructor, payout_type: "percentage", payout_percentage: 60)

    payout = CoursePayoutCalculator.new(offering).calculate!
    line = payout.line_items.first
    expect(line.payee).to eq(instructor)
    expect(line.amount_cents).to eq((payout.net_revenue_cents * 0.60).round)
  end

  it "pays a flat-fee instructor a fixed amount" do
    offering.course_offering_instructors.create!(person: instructor, payout_type: "flat", payout_cents: 3000)

    payout = CoursePayoutCalculator.new(offering).calculate!
    expect(payout.line_items.first.amount_cents).to eq(3000)
  end

  it "creates no line items when the split is 'none'" do
    offering.course_offering_instructors.create!(person: instructor, payout_type: "none")

    payout = CoursePayoutCalculator.new(offering).calculate!
    expect(payout.line_items).to be_empty
  end
end
