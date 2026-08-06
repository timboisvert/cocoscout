# frozen_string_literal: true

require "rails_helper"

# Deducted service charges belong inside the settlement that nets them out,
# not beside it as six things to chase.
RSpec.describe "Contract#payment_schedule_groups", type: :model do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) { create(:contract, :active, organization: org, production: production) }

  def settlement(due)
    contract.contract_payments.create!(description: "Ticket revenue less $750.00 fee — week of #{due.strftime('%b %-d')}",
                                       amount: 0, amount_tbd: true, direction: "outgoing", due_date: due)
  end

  def booth_tech(due)
    contract.contract_payments.create!(description: "Booth Tech — #{due.strftime('%b %-d, %Y')}", amount: 50,
                                       direction: "incoming", due_date: due, settlement_method: "payout_deduction")
  end

  it "folds each week's charges into that week's settlement" do
    week1 = settlement(Date.new(2026, 11, 7))
    week2 = settlement(Date.new(2026, 11, 14))
    [ 5, 6, 7 ].each { |d| booth_tech(Date.new(2026, 11, d)) }
    [ 12, 13, 14 ].each { |d| booth_tech(Date.new(2026, 11, d)) }

    groups = contract.payment_schedule_groups

    expect(groups.size).to eq(2)
    first = groups.find { |g| g[:payment] == week1 }
    expect(first[:deductions].size).to eq(3)
    expect(first[:deduction_total]).to eq(150.0)
    second = groups.find { |g| g[:payment] == week2 }
    expect(second[:deductions].size).to eq(3)
  end

  it "leaves a directly-collected charge as its own row" do
    settlement(Date.new(2026, 11, 7))
    direct = contract.contract_payments.create!(description: "Cleaning deposit", amount: 200,
                                                direction: "incoming", due_date: Date.new(2026, 11, 5))

    rows = contract.payment_schedule_groups.map { |g| g[:payment] }
    expect(rows).to include(direct)
  end

  it "leaves a deducted charge standing alone when there's no settlement to fold into" do
    charge = booth_tech(Date.new(2026, 11, 5))

    groups = contract.payment_schedule_groups
    expect(groups.map { |g| g[:payment] }).to eq([ charge ])
    expect(groups.first[:deductions]).to be_empty
  end

  it "keeps a paid charge visible instead of hiding it in a settlement" do
    settlement(Date.new(2026, 11, 7))
    paid = contract.contract_payments.create!(description: "Booth Tech — Nov 5, 2026", amount: 50,
                                              direction: "incoming", due_date: Date.new(2026, 11, 5),
                                              settlement_method: "payout_deduction",
                                              status: "paid", paid_date: Date.new(2026, 11, 5))

    expect(contract.payment_schedule_groups.map { |g| g[:payment] }).to include(paid)
  end
end
