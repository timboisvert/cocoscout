# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePayoutSettlement do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 4000) }

  # net revenue = $38 in these examples (fee already taken off the top).
  def payout(net_cents: 3800)
    offering.create_course_offering_payout!(status: "calculated", total_revenue_cents: net_cents,
                                            platform_fee_cents: 0, net_revenue_cents: net_cents,
                                            total_payout_cents: 0)
  end

  def amount_for(rows, name)
    rows.find { |r| r[:name] == name }&.dig(:amount_cents)
  end

  describe "scenario 2 & 3 — no contract, instructor paid from the org's share" do
    it "subtracts the instructor payment from what the org keeps" do
      p = payout(net_cents: 3800)
      instructor = create(:person, name: "John Smith")
      p.line_items.create!(payee: instructor, amount_cents: 1000, label: "John Smith",
                           calculation_details: { type: "instructor" })

      rows = described_class.new(p).rows
      expect(amount_for(rows, "John Smith")).to eq(1000)
      expect(described_class.new(p).org_keeps_cents).to eq(2800) # 3800 − 1000
      expect(amount_for(rows, org.name)).to eq(2800)
    end

    it "org keeps everything when no instructor is paid (scenario 3, paying yourself $0)" do
      p = payout(net_cents: 3800)
      expect(described_class.new(p).org_keeps_cents).to eq(3800)
    end
  end

  describe "scenario 1 — contract, instructor paid from the contractor's half" do
    let(:contractor) { create(:contractor, organization: org, name: "Janelle") }

    it "leaves the org's contractual share fixed and takes instructor pay off the contractor" do
      p = payout(net_cents: 3800)
      # Contract gives the contractor 50% of net = $19.
      p.line_items.create!(payee: contractor, amount_cents: 1900, label: "Janelle",
                           calculation_details: { type: "contract_revenue_share", share_percentage: 50 })
      # Org pays an instructor $5 — comes out of the contractor's half.
      instructor = create(:person, name: "Teacher")
      p.line_items.create!(payee: instructor, amount_cents: 500, label: "Teacher",
                           calculation_details: { type: "instructor" })

      settlement = described_class.new(p)
      rows = settlement.rows

      expect(amount_for(rows, "Janelle")).to eq(1400)  # 1900 − 500
      expect(amount_for(rows, "Teacher")).to eq(500)
      expect(settlement.org_keeps_cents).to eq(1900)   # net − contractor_share, unchanged
      expect(rows.sum { |r| r[:amount_cents] }).to eq(3800) # everything accounted for
    end
  end
end
