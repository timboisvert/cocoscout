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

  it "keeps a charge that was actually paid (cash/check) visible instead of hiding it in a settlement" do
    settlement(Date.new(2026, 11, 7))
    paid = contract.contract_payments.create!(description: "Booth Tech — Nov 5, 2026", amount: 50,
                                              direction: "incoming", due_date: Date.new(2026, 11, 5),
                                              settlement_method: "payout_deduction",
                                              status: "paid", paid_date: Date.new(2026, 11, 5),
                                              payment_method: "check")

    expect(contract.payment_schedule_groups.map { |g| g[:payment] }).to include(paid)
  end

  it "keeps a deduction-settled charge folded into its settlement — no money moved, so no Paid row" do
    host = settlement(Date.new(2026, 11, 7))
    fee = contract.contract_payments.create!(description: "Booth Tech — Nov 7, 2026", amount: 50,
                                             direction: "incoming", due_date: Date.new(2026, 11, 7),
                                             settlement_method: "payout_deduction",
                                             status: "paid", paid_date: Date.new(2026, 11, 7),
                                             payment_method: "payout_deduction")

    groups = contract.payment_schedule_groups
    expect(groups.map { |g| g[:payment] }).not_to include(fee)
    host_group = groups.find { |g| g[:payment] == host }
    expect(host_group[:deductions]).to include(fee)
  end

  it "folds a deducted fee into its own settlement even once that settlement is paid" do
    earlier = contract.contract_payments.create!(description: "Revenue Share - Event 1", amount: 320,
                                                 direction: "outgoing", due_date: Date.new(2026, 10, 3),
                                                 status: "paid", paid_date: Date.new(2026, 10, 5))
    host = contract.contract_payments.create!(description: "Nov 7 — 50% to them", amount: 257.50,
                                              direction: "outgoing", due_date: Date.new(2026, 11, 7),
                                              status: "paid", paid_date: Date.new(2026, 11, 9))
    fee = contract.contract_payments.create!(description: "Booth Tech — Nov 7, 2026", amount: 50,
                                             direction: "incoming", due_date: Date.new(2026, 11, 7),
                                             settlement_method: "payout_deduction",
                                             status: "paid", paid_date: Date.new(2026, 11, 7),
                                             payment_method: "payout_deduction")

    groups = contract.payment_schedule_groups
    expect(groups.map { |g| g[:payment] }).not_to include(fee)
    expect(groups.find { |g| g[:payment] == earlier }[:deductions]).to be_empty
    expect(groups.find { |g| g[:payment] == host }[:deductions]).to eq([ fee ])
  end
end
