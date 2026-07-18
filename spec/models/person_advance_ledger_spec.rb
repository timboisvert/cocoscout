# frozen_string_literal: true

require "rails_helper"

# Advances now flow through the performer payout run: issuing adds a payout, and
# the ledger effect lands when the run pays (driving the balance negative), so
# future earnings net against it. No self-posted `advance` entry, no
# remaining_balance drift.
RSpec.describe "Advance via payout run (ledger)" do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:person) { create(:person, name: "Advance Andy", stripe_account_id: "acct_a", payouts_enabled: true) }
  let(:issuer) { create(:user) }

  def issue(cents = 5000)
    AdvancePayoutService.issue!(person: person, amount_cents: cents, production: production, issued_by: issuer)
  end

  def pay!(batch)
    allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_a"))
    PayoutBatchService.process!(batch)
  end

  it "doesn't hit the ledger until the run pays" do
    issue
    expect(org.payout_balance_cents_for(person, category: "performer")).to eq(0)
  end

  it "drives the balance negative when paid, then nets against later earnings" do
    result = issue(5000)
    pay!(result.batch)
    expect(org.payout_balance_cents_for(person, category: "performer")).to eq(-5000) # advanced $50

    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "earning",
                            amount_cents: 10_000, category: "performer")
    expect(org.payout_balance_cents_for(person, category: "performer")).to eq(5000) # $100 earned − $50 advance
  end

  it "marks the advance paid (via stripe) when the run pays" do
    result = issue(5000)
    pay!(result.batch)
    expect(result.advance.reload).to be_paid
    expect(result.advance.payment_method).to eq("stripe")
  end

  it "puts the advance on the open performer run as a contribution" do
    result = issue(4000)
    item = result.batch.items.find_by(payee: person)
    expect(result.batch.kind).to eq("performer")
    expect(item.amount_cents).to eq(4000)
    expect(item.payout_contributions.first.source).to eq(result.advance)
    expect(result.advance.in_payout_run?).to be(true)
  end
end
