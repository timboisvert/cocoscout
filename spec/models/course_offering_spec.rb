# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseOffering, type: :model do
  describe "#sessions (per-offering scoping)" do
    let(:org) { create(:organization, :pro) }
    let(:production) { create(:production, organization: org, production_type: "course") }
    let(:run_a) { create(:course_offering, production: production) }
    let(:run_b) { create(:course_offering, production: production) }

    it "returns only this run's sessions, not other runs' on the same production" do
      a1 = create(:show, production: production, course_offering: run_a, event_type: "class", date_and_time: 1.week.from_now)
      a2 = create(:show, production: production, course_offering: run_a, event_type: "class", date_and_time: 2.weeks.from_now)
      create(:show, production: production, course_offering: run_b, event_type: "class", date_and_time: 3.weeks.from_now)

      expect(run_a.sessions).to contain_exactly(a1, a2)
      expect(run_b.sessions.count).to eq(1)
    end

    it "ignores shows on the production that belong to no offering" do
      create(:show, production: production, course_offering: nil, event_type: "class", date_and_time: 1.week.from_now)
      expect(run_a.sessions).to be_empty
    end

    it "orders sessions by date" do
      later = create(:show, production: production, course_offering: run_a, event_type: "class", date_and_time: 2.weeks.from_now)
      earlier = create(:show, production: production, course_offering: run_a, event_type: "class", date_and_time: 1.week.from_now)
      expect(run_a.sessions.to_a).to eq([ earlier, later ])
    end

    it "unlinks (does not delete) its session shows when the run is destroyed" do
      show = create(:show, production: production, course_offering: run_a, event_type: "class", date_and_time: 1.week.from_now)
      expect { run_a.destroy }.not_to raise_error
      expect(Show.exists?(show.id)).to be true          # show survives
      expect(show.reload.course_offering_id).to be_nil  # just unlinked
    end
  end

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
