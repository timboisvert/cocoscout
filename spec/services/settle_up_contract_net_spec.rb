# frozen_string_literal: true

require "rails_helper"

# A contract show's share on the Settle up day is what actually goes out:
# the share less what they owe that comes out of it (Tim, 2026-11-11: the
# day said $106.00 by contract where the contract and Payouts said $6.00).
RSpec.describe SettleUp do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) { create(:contract, :active, organization: org, production: production) }
  let(:share) { contract.contract_payments.create!(description: "Nov 11 — 40% to them", amount: 106, direction: "outgoing", due_date: Date.new(2026, 11, 11)) }

  def booth_tech(due, amount: 50)
    contract.contract_payments.create!(description: "Booth Tech — #{due.strftime('%b %-d, %Y')}", amount: amount,
                                       direction: "incoming", due_date: due, settlement_method: "payout_deduction")
  end

  it "nets the charges taken out of a share" do
    charges = [ booth_tech(Date.new(2026, 11, 9)), booth_tech(Date.new(2026, 11, 11)) ]

    taken = described_class.contract_deductions([ share ])

    expect(taken).to eq(share.id => charges)
    expect(described_class.contract_net_cents(share, taken)).to eq(600)
    expect(described_class.contract_net_cents(share)).to eq(600)
  end

  # What the day actually made: takings less what goes to the shows'
  # people. What they owe for services is kept back from their share, so it
  # is less going out, never an expense.
  it "works out what the house keeps from a day" do
    show = create(:show, production: production, date_and_time: Time.zone.local(2026, 11, 11, 19))
    ShowFinancials.create!(show: show, revenue_type: "ticket_sales", ticket_revenue: 265, ticket_count: 13)
    share.update!(show: show)
    booth_tech(Date.new(2026, 11, 9))
    booth_tech(Date.new(2026, 11, 11))

    day = described_class.day(org, Date.new(2026, 11, 11))

    expect(day.in_cents).to eq(26_500)
    expect(day.to_people_cents).to eq(600)
    expect(day.kept_back_cents).to eq(10_000)
    expect(day.house_keeps_cents).to eq(25_900)
  end

  it "is the whole share when nothing comes out of it, and never less than nothing" do
    expect(described_class.contract_deductions([ share ])).to eq({})
    expect(described_class.contract_net_cents(share)).to eq(10_600)

    booth_tech(Date.new(2026, 11, 9), amount: 150)
    expect(described_class.contract_net_cents(share)).to eq(0)
  end

  # Once the run has gone out the charge is paid, by deduction: the share
  # still went out net of it, and the day still says so.
  it "keeps a charge that already came out on the run, and leaves out one collected on its own" do
    taken = booth_tech(Date.new(2026, 11, 9))
    taken.update!(status: "paid", paid_date: Date.new(2026, 11, 9), payment_method: "payout_deduction")
    contract.contract_payments.create!(description: "Cleaning deposit", amount: 200, direction: "incoming", due_date: Date.new(2026, 11, 10))

    expect(described_class.contract_deductions([ share ])).to eq(share.id => [ taken ])
    expect(described_class.contract_net_cents(share)).to eq(5_600)
  end
end
