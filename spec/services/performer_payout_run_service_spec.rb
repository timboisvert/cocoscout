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
end
