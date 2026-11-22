# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tax::YearEarnings, type: :service do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person) }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 5_000) }
  let(:tax_year) { 2025 }

  def paid_batch_item(cents:, paid_at:, reimbursement_cents: 0, category: "staffing")
    batch = create(:payout_batch, organization: org, kind: "staff_pay", status: "completed", payday: paid_at.to_date)
    item = PayoutBatchItem.create!(payout_batch: batch, payee: person, amount_cents: cents, status: "pending")
    PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: person, category: category,
                               amount_cents: cents - reimbursement_cents, label: "Worked hours (5h)")
    if reimbursement_cents.positive?
      PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: person, category: category,
                                 amount_cents: reimbursement_cents, label: "Reimbursement")
    end
    item.update!(status: "paid", paid_at: paid_at)
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "payout",
                            amount_cents: -cents, source: item, description: "test payout",
                            occurred_at: paid_at, category: category)
    item
  end

  it "adds show pay to staff pay, since one payer sends one person one 1099 (Tim, 2026-11-22)" do
    paid_batch_item(cents: 100_000, paid_at: Time.zone.local(2025, 6, 1))
    paid_batch_item(cents: 80_000, paid_at: Time.zone.local(2025, 7, 1), category: "performer")

    expect(described_class.for(org, tax_year)[person.id].paid_cents).to eq(180_000)
  end

  it "counts a contract payment paid to the contractor by hand (Tim, 2026-11-22)" do
    contractor = create(:contractor, organization: org, name: "Carded LLC", person: person)
    contract = create(:contract, :active, organization: org, contractor: contractor, contractor_name: "Carded LLC")
    paid = contract.contract_payments.create!(description: "Apr 2 show", amount: 700, direction: "outgoing", due_date: Date.new(2025, 4, 2))
    paid.pay_offline!(method: "check", paid_on: Date.new(2025, 4, 3))
    contract.contract_payments.create!(description: "Not paid", amount: 300, direction: "outgoing", due_date: Date.new(2025, 5, 2))
    contract.contract_payments.create!(description: "They paid us", amount: 900, direction: "incoming", due_date: Date.new(2025, 5, 2),
                                       status: "paid", payment_method: "check", paid_date: Date.new(2025, 5, 3))

    result = described_class.for(org, tax_year)[person.id]
    expect(result.paid_cents).to eq(700_00)
    expect(result.offline_cents).to eq(700_00)
  end

  it "counts show pay marked paid another way, and leaves out money paid to an organization" do
    production = create(:production, organization: org)
    show = create(:show, production: production, date_and_time: Time.zone.local(2025, 4, 1, 20))
    payout = ShowPayout.create!(show: show, status: "paid")
    line = ShowPayoutLineItem.create!(show_payout: payout, payee: person, amount: 450)
    PayoutLedgerEntry.post!(organization: org, payee: line.payee, entry_type: "payout", amount_cents: -450_00,
                            source: line, occurred_at: Time.zone.local(2025, 4, 2), category: "performer")
    PayoutLedgerEntry.post!(organization: org, payee: create(:organization), entry_type: "payout", amount_cents: -900_00,
                            occurred_at: Time.zone.local(2025, 4, 2), category: "performer")

    expect(described_class.for(org, tax_year)[person.id].paid_cents).to eq(450_00)
    expect(described_class.for(org, tax_year).keys).to eq([ person.id ])
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
