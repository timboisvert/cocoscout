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

# A registration changing state (refund, cancel, confirm) has to bring the
# payout back in line with what the course actually took in. Nothing is owed
# out of money that was handed back.
RSpec.describe CoursePayoutCalculator, "#resync!" do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 5000) }
  let(:instructor) { create(:person) }
  let!(:registrations) do
    3.times.map { create(:course_registration, course_offering: offering, amount_cents: 5000, cocoscout_fee_cents: 500, status: "confirmed") }
  end

  def payout
    offering.course_offering_payout.reload
  end

  context "a percentage instructor on a course that gets fully refunded" do
    before do
      offering.course_offering_instructors.create!(person: instructor, payout_type: "percentage", payout_percentage: 20)
      described_class.new(offering).calculate!
      expect(payout.line_items.sum(:amount_cents)).to eq(2700) # 20% of $135 net
    end

    it "dissolves the payout when every registration is refunded" do
      registrations.each(&:refund!)

      expect(payout.total_revenue_cents).to eq(0)
      expect(payout.net_revenue_cents).to eq(0)
      expect(payout.total_payout_cents).to eq(0)
      expect(payout.line_items).to be_empty
      expect(offering.reload.financials_summary).to include(gross_cents: 0, payout_cents: 0, net_cents: 0)
    end

    it "rescales the instructor's share when one registration is refunded" do
      registrations.first.refund!

      expect(payout.net_revenue_cents).to eq(9000)
      expect(payout.line_items.sum(:amount_cents)).to eq(1800) # 20% of $90
      expect(payout.total_payout_cents).to eq(1800)
    end

    it "pulls the instructor off an open payout run so the run re-totals" do
      CoursePayoutRunService.add_to_run!(payout, added_by: nil)
      line = payout.line_items.first
      contribution = PayoutContribution.find_by(source: line)
      batch = contribution.payout_batch
      expect(batch.items.count).to be >= 1

      registrations.each(&:refund!)

      expect(PayoutContribution.find_by(source: line)).to be_nil
      expect(CourseOfferingPayoutLineItem.exists?(line.id)).to be false
      expect(PayoutContribution.where(source: offering.course_offering_payout)).to be_empty
    end

    it "leaves an instructor already paid on a run alone" do
      CoursePayoutRunService.add_to_run!(payout, added_by: nil)
      line = payout.line_items.first
      item = PayoutContribution.find_by(source: line).payout_batch_item
      item.update!(status: "paid", paid_at: Time.current)

      registrations.each(&:refund!)

      expect(CourseOfferingPayoutLineItem.exists?(line.id)).to be true
      expect(line.reload.amount_cents).to eq(2700)
    end
  end

  it "keeps a hand-entered instructor amount on a partial refund, drops it on a full one" do
    described_class.new(offering).calculate!
    typed = payout.line_items.create!(payee: instructor, amount_cents: 4000, label: instructor.name,
                                      calculation_details: { type: "instructor", person_id: instructor.id })

    registrations.first.refund!
    expect(CourseOfferingPayoutLineItem.exists?(typed.id)).to be true
    expect(typed.reload.amount_cents).to eq(4000)

    registrations.drop(1).each(&:refund!)
    expect(CourseOfferingPayoutLineItem.exists?(typed.id)).to be false
  end

  it "does nothing once the payout has been paid" do
    offering.course_offering_instructors.create!(person: instructor, payout_type: "percentage", payout_percentage: 20)
    described_class.new(offering).calculate!
    payout.update!(status: "paid", paid_at: Time.current)

    registrations.each(&:refund!)

    expect(payout.line_items.sum(:amount_cents)).to eq(2700)
  end

  it "calculate! clears the old line items even when the deal now produces none" do
    offering.course_offering_instructors.create!(person: instructor, payout_type: "percentage", payout_percentage: 20)
    described_class.new(offering).calculate!
    registrations.each { |r| r.update_columns(status: "refunded") } # bypass callbacks: simulate stale state

    described_class.new(offering).calculate!

    expect(payout.line_items).to be_empty
    expect(payout.total_payout_cents).to eq(0)
  end
end
