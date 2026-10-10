# frozen_string_literal: true

require "rails_helper"

# Contract 113 (Tim, 2026-10-10): a course under a contract settles the
# contractor's share in its course payout, but the contract's own settlement
# sat "TBD, 13 days overdue, awaiting ticket sales" after the $75.60 payout
# went out. The old sync looked for a Contractor payee and a "revenue share"
# description; course payouts pay the contractor's Person now.
RSpec.describe CourseOfferingPayout, "and the contract it settles" do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person, name: "Dan Feltey") }
  let(:contractor) { create(:contractor, organization: org, person: person, name: "Dan Feltey") }
  let(:production) { create(:production, organization: org, production_type: "course", name: "Card Magic for Beginners") }
  let(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: contractor.name)
  end
  let(:offering) { create(:course_offering, production: production, contract: contract) }
  let!(:session) { create(:show, production: production, course_offering: offering, date_and_time: Time.zone.local(2026, 9, 27, 14)) }
  let!(:settlement) do
    create(:contract_payment, :outgoing, contract: contract, description: "Sep 27 — 50% to them", amount: 0, amount_tbd: true,
                                         due_date: Date.new(2026, 9, 27), show: session)
  end
  let(:payout) do
    offering.create_course_offering_payout!(status: "calculated", total_revenue_cents: 15_120, platform_fee_cents: 0,
                                            net_revenue_cents: 15_120, total_payout_cents: 7_560)
  end
  let!(:line) { payout.line_items.create!(payee: person, amount_cents: 7_560, label: "Dan Feltey", calculation_details: { type: "contract_revenue_share" }) }

  it "pays the contract's settlement when the line is paid by hand" do
    line.mark_paid!(user: nil, method: "zelle")

    expect(settlement.reload).to have_attributes(status: "paid", payment_method: "course_payout", amount: 75.60.to_d, amount_tbd: false)
    expect(settlement.notes).to include("Auto-synced from course payout")
  end

  it "pays it when the line goes out on a payout run" do
    line.mark_paid_via_payout_run!(reference_id: "tr_1")

    expect(settlement.reload).to have_attributes(status: "paid", payment_method: "course_payout", amount: 75.60.to_d)
  end

  it "heals a run paid before this, when the contract is opened, and touches nothing twice" do
    line.update_columns(manually_paid: true, paid_at: Time.zone.local(2026, 10, 6, 12), payment_method: "stripe")
    expect(settlement.reload).to be_status_pending

    contract.sync_course_payouts_to_payments
    expect(settlement.reload).to have_attributes(status: "paid", paid_date: Date.new(2026, 10, 6), amount: 75.60.to_d)

    expect { contract.sync_course_payouts_to_payments }.not_to(change { settlement.reload.updated_at })
  end

  it "settles every session's settlement, the last carrying the amount" do
    later = create(:show, production: production, course_offering: offering, date_and_time: Time.zone.local(2026, 10, 4, 14))
    second = create(:contract_payment, :outgoing, contract: contract, description: "Oct 4 — 50% to them", amount: 0, amount_tbd: true,
                                                  due_date: Date.new(2026, 10, 4), show: later)
    line.mark_paid!(user: nil, method: "zelle")

    expect([ settlement.reload, second.reload ].map { |p| [ p.status, p.amount ] }).to eq([ [ "paid", 0.to_d ], [ "paid", 75.60.to_d ] ])
  end

  it "leaves the contract alone for a line paid to someone else" do
    other = payout.line_items.create!(payee: create(:person), amount_cents: 1_000, label: "Guest teacher", calculation_details: { type: "instructor" })
    other.mark_paid!(user: nil, method: "cash")

    expect(settlement.reload).to be_status_pending
  end
end
