# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PersonAdvance ledger sync" do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org) }
  let(:person) { create(:person, name: "Advance Andy") }

  def advance(**attrs)
    create(:person_advance, :paid, person: person, production: production,
           original_amount: 50, remaining_balance: 50, **attrs)
  end

  it "posts a negative advance entry for a paid advance's outstanding balance" do
    advance
    expect(org.payout_balance_cents_for(person)).to eq(-5000)
  end

  it "does not post for an unpaid advance" do
    create(:person_advance, person: person, production: production, original_amount: 50, remaining_balance: 50)
    expect(org.payout_balance_cents_for(person)).to eq(0)
  end

  it "shrinks as the advance is recovered and clears when settled" do
    a = advance
    a.update!(remaining_balance: 20, status: "partial")
    expect(org.payout_balance_cents_for(person)).to eq(-2000)

    a.update!(remaining_balance: 0, status: "settled")
    expect(org.payout_balance_cents_for(person)).to eq(0)
  end

  it "removes the entry when the advance is written off" do
    a = advance
    a.write_off!(notes: "gift")
    expect(org.payout_balance_cents_for(person)).to eq(0)
  end

  it "nets correctly against an earning (earned 100, advanced 50 → owed 50)" do
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "earning", amount_cents: 10_000, source: production)
    advance
    expect(org.payout_balance_cents_for(person)).to eq(5000)
  end
end
