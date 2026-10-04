# frozen_string_literal: true

require "rails_helper"

# Tax on course registrations: the theater's one course-tax setting, the
# checkout's quote (added on top or inside the price), the lines a paid
# registration leaves behind, and their reversal on a refund. The tax rides
# to the org's balance and never into fees or the instructor split.
RSpec.describe CourseTax do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 15_000) }

  it "quotes nothing until the theater sets a course tax, then adds it on top or finds it inside" do
    expect(described_class.quote(offering).tax_cents).to eq(0)
    expect(described_class.price_note(offering)).to be_nil

    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "10.25", mode: "added")
    q = described_class.quote(offering)
    expect([ q.base_cents, q.tax_cents, q.mode, q.added?, q.total_cents, q.label ]).to eq([ 15_000, 1_538, "added", true, 16_538, "Sales tax 10.25%" ])
    expect(described_class.price_note(offering)).to eq("+ sales tax 10.25%")
    # Tickets keep their own setting.
    expect(TicketTaxSetting.current(org).set?).to be(false)

    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "10.25", mode: "included")
    q = described_class.quote(offering)
    expect([ q.base_cents, q.tax_cents, q.mode, q.added?, q.total_cents ]).to eq([ 15_000 - 1_395, 1_395, "included", false, 15_000 ])
    expect(described_class.price_note(offering)).to eq("incl. sales tax 10.25%")
  end

  it "records a paid registration's tax, carries it to the org's money, keeps it out of fees, and reverses it on refund" do
    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "10.25", mode: "added")
    registration = offering.course_registrations.create!(
      person: create(:person), status: :confirmed, amount_cents: 15_000, tax_cents: 1_538, currency: "usd",
      registered_at: Time.current, paid_at: Time.current, stripe_checkout_session_id: "cs_tax", stripe_payment_intent_id: "pi_tax",
      cocoscout_fee_cents: CourseRegistration.platform_fee_cents_for(offering, 15_000)
    )
    described_class.record!(registration)
    described_class.record!(registration) # once

    line = registration.tax_lines.sole
    expect([ line.name, line.rate_bps, line.base_cents, line.tax_cents, line.included ]).to eq([ "Sales tax", 1_025, 15_000, 1_538, false ])
    # The fee is on the price; the org is owed price − fee + tax.
    expect(registration.cocoscout_fee_cents).to eq(1_500)
    expect(registration.org_net_cents).to eq(15_000 - 1_500 + 1_538)
    expect(OrgPayout.owed_cents_for_course(offering)).to eq(15_000 - 1_500 + 1_538)
    expect(OrgCashEntry.find_by(source: registration, entry_type: "course_registration").amount_cents).to eq(15_038)
    expect(CoursePayoutCalculator.new(offering).revenue_summary[:total_revenue_cents]).to eq(15_000)
    expect(CourseMoneyStatement.new(offering).totals[:tax_cents]).to eq(1_538)

    report = TicketTaxReport.new(org, from: Date.current.beginning_of_month, to: Date.current.end_of_month, kind: "courses")
    expect(report.rows.sole.collected_cents).to eq(1_538)
    expect(TicketTaxReport.new(org, from: Date.current.beginning_of_month, to: Date.current.end_of_month, kind: "tickets").rows).to be_empty

    registration.refund!
    expect(registration.tax_lines.where.not(reversal_of_id: nil).sole.tax_cents).to eq(-1_538)
    after = TicketTaxReport.new(org, from: Date.current.beginning_of_month, to: Date.current.end_of_month, kind: "courses")
    expect([ after.rows.sole.refunded_cents, after.rows.sole.net_cents ]).to eq([ -1_538, 0 ])
  end
end
