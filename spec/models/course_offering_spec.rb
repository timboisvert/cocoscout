# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseOffering, type: :model do
  describe "#financials_summary" do
    let(:org) { create(:organization) }
    let(:production) { create(:production, organization: org, production_type: "course") }
    let(:offering) { create(:course_offering, production: production, price_cents: 4000) }

    it "counts money kept as the confirmed sum, not confirmed minus refunds" do
      # Three $40 registrations, two later refunded → only $40 kept.
      create(:course_registration, course_offering: offering, amount_cents: 4000, status: "confirmed")
      create(:course_registration, course_offering: offering, amount_cents: 4000, status: "refunded")
      create(:course_registration, course_offering: offering, amount_cents: 4000, status: "refunded")

      summary = offering.financials_summary
      expect(summary[:gross_cents]).to eq(4000)     # not -4000
      expect(summary[:confirmed_count]).to eq(1)
      expect(summary[:refunded_count]).to eq(2)
    end

    it "nets a fully-refunded course to zero, not negative" do
      create(:course_registration, course_offering: offering, amount_cents: 4000, status: "refunded")
      summary = offering.financials_summary
      expect(summary[:gross_cents]).to eq(0)
      expect(summary[:net_cents]).to eq(0)
    end
  end
end
