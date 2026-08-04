# frozen_string_literal: true

require "rails_helper"

RSpec.describe PerformerPayoutRunService do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }
  let(:person) { create(:person, stripe_account_id: "acct_p", payouts_enabled: true) }
  let(:show_payout) { create(:show_payout, show: show) }
  let!(:line) { show_payout.line_items.create!(payee: person, amount: 200, shares: 1) }

  # A prior $advance already paid out to the person (a negative performer entry).
  def advance!(cents)
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "payout",
                            amount_cents: -cents, category: "performer", description: "advance")
  end

  it "creates an item paying the payee's net performer balance" do
    result = described_class.add_show_payout!(show_payout)
    item = result.batch.items.find_by(payee: person)
    expect(item.amount_cents).to eq(20_000)
    expect(org.payout_balance_cents_for(person, category: "performer")).to eq(20_000)
  end

  it "adds a performer who hasn't connected a bank — their money rides the run" do
    no_bank = create(:person) # no stripe_account_id → can_receive_payouts? is false
    show_payout.line_items.create!(payee: no_bank, amount: 50, shares: 1)

    result = described_class.add_show_payout!(show_payout)
    # Same model as staffing: they're on the run (item pending); the funded run
    # holds their money and pay_remaining! sends it once they connect.
    expect(result.batch.items.find_by(payee: no_bank)).to be_present
    expect(result.batch.items.find_by(payee: no_bank).status).to eq("pending")
    expect(result.batch.items.find_by(payee: person)).to be_present
  end

  it "subtracts an outstanding advance from what the run pays (net balance)" do
    advance!(10_000) # $100 advanced earlier
    item = described_class.add_show_payout!(show_payout).batch.items.find_by(payee: person)
    expect(item.amount_cents).to eq(10_000) # $200 earned − $100 advance
  end

  it "pays nothing (drops the item) when an outstanding advance exceeds earnings" do
    advance!(30_000) # advanced more than they earned
    result = described_class.add_show_payout!(show_payout)
    expect(result.batch.items.find_by(payee: person)).to be_nil
  end

  it "ignores staff pay when settling a performer run" do
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "earning",
                            amount_cents: 5_000, category: "staffing", description: "staff")
    item = described_class.add_show_payout!(show_payout).batch.items.find_by(payee: person)
    expect(item.amount_cents).to eq(20_000) # only the $200 performer earning, not the $50 staff
  end

  it "is idempotent — re-adding the same show doesn't double the contribution or amount" do
    described_class.add_show_payout!(show_payout)
    result = described_class.add_show_payout!(show_payout)
    item = result.batch.items.find_by(payee: person)
    expect(item.amount_cents).to eq(20_000)
    expect(item.payout_contributions.count).to eq(1)
  end

  it "drops an unpaid item when its only show is recalculated away" do
    result = described_class.add_show_payout!(show_payout)
    expect(result.batch.items.find_by(payee: person)).to be_present
    line.destroy! # recalc cascades: contribution + earning entry
    expect(result.batch.items.find_by(payee: person)).to be_nil
  end

  it "re-settles an unpaid item to the remaining net when one of several shows is recalculated away" do
    show2 = create(:show, production: production)
    sp2 = create(:show_payout, show: show2)
    sp2.line_items.create!(payee: person, amount: 100, shares: 1)

    described_class.add_show_payout!(show_payout) # $200
    result = described_class.add_show_payout!(sp2)  # + $100
    item = result.batch.items.find_by(payee: person)
    expect(item.amount_cents).to eq(30_000)

    line.destroy! # remove the $200 show
    expect(item.reload.amount_cents).to eq(10_000) # only the $100 show remains
  end
end
