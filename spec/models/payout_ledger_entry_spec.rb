# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutLedgerEntry, type: :model do
  let(:organization) { create(:organization, :pro) }
  let(:person) { create(:person) }
  let(:production) { create(:production, organization: organization) }

  describe ".post! and balances" do
    it "posts an earning and reflects it in the org balance" do
      PayoutLedgerEntry.post!(organization: organization, payee: person,
                              entry_type: "earning", amount_cents: 6000)
      expect(organization.payout_balance_cents_for(person)).to eq(6000)
    end

    it "is idempotent per source: re-posting the same source restates, never double-counts" do
      show = create(:show, production: production)
      sp = ShowPayout.create!(show: show, status: "awaiting_payout")
      line_item = sp.line_items.create!(payee: person, amount: 60, shares: 1)

      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "earning",
                              amount_cents: 6000, source: line_item)
      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "earning",
                              amount_cents: 4000, source: line_item)

      expect(PayoutLedgerEntry.where(source: line_item, entry_type: "earning").count).to eq(1)
      expect(organization.payout_balance_cents_for(person)).to eq(4000)
    end

    it "nets advances (negative) against earnings" do
      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "earning", amount_cents: 6000)
      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "advance", amount_cents: -1000)
      expect(organization.payout_balance_cents_for(person)).to eq(5000)
    end

    it "debits payouts and settles to zero" do
      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "earning", amount_cents: 5000)
      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "payout", amount_cents: -5000)
      expect(organization.payout_balance_cents_for(person)).to eq(0)
    end

    it "aggregates a company-wide balance across productions" do
      prod_a = create(:production, organization: organization)
      prod_b = create(:production, organization: organization)
      show_a = create(:show, production: prod_a)
      show_b = create(:show, production: prod_b)
      li_a = ShowPayout.create!(show: show_a, status: "awaiting_payout").line_items.create!(payee: person, amount: 30, shares: 1)
      li_b = ShowPayout.create!(show: show_b, status: "awaiting_payout").line_items.create!(payee: person, amount: 45, shares: 1)

      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "earning", amount_cents: 3000, source: li_a)
      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "earning", amount_cents: 4500, source: li_b)

      expect(organization.payout_balance_cents_for(person)).to eq(7500)
    end
  end

  describe ".unpost!" do
    it "removes the entry a source posted" do
      show = create(:show, production: production)
      li = ShowPayout.create!(show: show, status: "awaiting_payout").line_items.create!(payee: person, amount: 20, shares: 1)
      PayoutLedgerEntry.post!(organization: organization, payee: person, entry_type: "earning", amount_cents: 2000, source: li)

      expect { PayoutLedgerEntry.unpost!(source: li, entry_type: "earning") }
        .to change { organization.payout_balance_cents_for(person) }.from(2000).to(0)
    end
  end

  describe "validations" do
    it "rejects an unknown entry_type" do
      entry = PayoutLedgerEntry.new(organization: organization, payee: person,
                                    entry_type: "bogus", amount_cents: 100, occurred_at: Time.current)
      expect(entry).not_to be_valid
    end
  end
end
