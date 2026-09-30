# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tax::YearEarnings, type: :service do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person) }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 5_000) }
  let(:tax_year) { 2025 }

  def paid_batch_item(cents:, paid_at:, reimbursement_cents: 0)
    batch = create(:payout_batch, organization: org, kind: "staff_pay", status: "completed", payday: paid_at.to_date)
    item = PayoutBatchItem.create!(payout_batch: batch, payee: person, amount_cents: cents, status: "pending")
    PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: person, category: "staffing",
                               amount_cents: cents - reimbursement_cents, label: "Worked hours (5h)")
    if reimbursement_cents.positive?
      PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: person, category: "staffing",
                                 amount_cents: reimbursement_cents, label: "Reimbursement")
    end
    item.update!(status: "paid", paid_at: paid_at)
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "payout",
                            amount_cents: -cents, source: item, description: "test payout",
                            occurred_at: paid_at, category: "staffing")
    item
  end

  it "totals in-year staff payouts by payee, cash basis" do
    paid_batch_item(cents: 200_000, paid_at: Time.zone.local(2025, 6, 1))
    paid_batch_item(cents: 100_000, paid_at: Time.zone.local(2025, 11, 15))
    paid_batch_item(cents: 500_000, paid_at: Time.zone.local(2024, 12, 15))

    result = described_class.for(org, tax_year)[person.id]
    expect(result.paid_cents).to eq(300_000)
    expect(result.onchain_cents).to eq(300_000)
  end

  it "peels reimbursements off (not 1099 income) but keeps them on the record" do
    paid_batch_item(cents: 250_000, paid_at: Time.zone.local(2025, 5, 1), reimbursement_cents: 50_000)

    result = described_class.for(org, tax_year)[person.id]
    expect(result.paid_cents).to eq(200_000)
    expect(result.reimbursement_cents).to eq(50_000)
  end

  it "adds offline-paid time entries, minus any reimbursement portion" do
    entry = create(:staff_time_entry, organization: org, person: person,
                   started_at: Time.zone.local(2025, 3, 10, 18), ended_at: Time.zone.local(2025, 3, 10, 23))
    entry.mark_paid_offline!(create(:user), amount_cents: 300_00, reimbursement_cents: 50_00, paid_on: "2025-03-11")

    result = described_class.for(org, tax_year)[person.id]
    # offline_amount_cents ($300) is the wages portion; offline_reimbursement_cents
    # ($50) is the separate expense refund. Reportable = $300; the $50 is
    # tracked but not on the 1099.
    expect(result.paid_cents).to eq(300_00)
    expect(result.offline_cents).to eq(300_00)
    expect(result.reimbursement_cents).to eq(50_00)
  end

  it "prices offline entries at the member's rate when no amount was recorded" do
    create(:staff_time_entry, organization: org, person: person,
           started_at: Time.zone.local(2025, 3, 10, 18), ended_at: Time.zone.local(2025, 3, 10, 23))
      .mark_paid_offline!(create(:user), paid_on: "2025-03-11")

    result = described_class.for(org, tax_year)[person.id]
    expect(result.paid_cents).to eq(250_00)
  end

  it "backs out reversals (bank returns)" do
    item = paid_batch_item(cents: 100_00, paid_at: Time.zone.local(2025, 4, 1))
    travel_to Time.zone.local(2025, 4, 8) do
      item.mark_returned!(reason: "closed account")
    end

    result = described_class.for(org, tax_year)[person.id]
    expect(result.paid_cents).to eq(0)
    expect(result.onchain_return_cents).to eq(100_00)
  end
end
