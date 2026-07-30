# frozen_string_literal: true

require "rails_helper"

# Deep checks on the net-balance / advance model: the money math, edge cases,
# the paid-item guard, and that legacy (pre-rebuild) advance history still
# recoups correctly.
RSpec.describe "Payout net-balance and advances" do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:person) { create(:person, name: "Neta Netto", stripe_account_id: "acct_p", payouts_enabled: true) }
  let(:issuer) { create(:user) }

  def earn(cents, category: "performer")
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "earning",
                            amount_cents: cents, category: category, description: "earning #{SecureRandom.hex(3)}")
  end

  def perf_balance
    org.payout_balance_cents_for(person, category: "performer")
  end

  def issue_advance(cents)
    AdvancePayoutService.issue!(person: person, amount_cents: cents, production: production, issued_by: issuer)
  end

  def pay!(batch)
    allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_#{SecureRandom.hex(3)}"))
    PayoutBatchService.process!(batch)
  end

  # Settle a fresh performer run whose in-run earning is `earning_cents` — mirrors a
  # show payout riding the run as a contribution (the earning itself is on the
  # ledger via `earn`). An item now pays min(net balance, in-run earnings), so the
  # run must actually carry the earning as a contribution. Returns the item or nil.
  def settle_run(earning_cents)
    batch = PayoutBatch.open_for(org, kind: "performer")
    item = batch.items.create!(payee: person, amount_cents: 1, status: "pending")
    if earning_cents.positive?
      # A real performer earning contribution carries a source (a ShowPayoutLineItem);
      # the in-run-earnings query excludes NULL source_type, so give it a source.
      item.payout_contributions.create!(payout_batch: batch, payee: person, label: "Show pay",
                                        amount_cents: earning_cents, source: create(:show, production: production))
    end
    item.settle_performer_amount!
  end

  it "pays an advance ALONGSIDE earnings in the same run, leaving the advance owed" do
    earn(20_000) # $200 earned
    result = issue_advance(10_000) # + $100 advance in the same open run
    item = result.batch.items.find_by(payee: person)
    # The $200 show pay rides the same run as a contribution (real flow).
    item.payout_contributions.create!(payout_batch: result.batch, payee: person, label: "Show pay",
                                      amount_cents: 20_000, source: create(:show, production: production))
    item.settle_performer_amount!
    expect(item.amount_cents).to eq(30_000) # gets paid $200 owed + $100 advance

    pay!(result.batch)
    expect(perf_balance).to eq(-10_000) # earned 200, paid 300 → owes the $100 advance
  end

  it "recoups a large advance across multiple later earnings" do
    result = issue_advance(30_000) # $300 advance, nothing earned yet
    pay!(result.batch)
    expect(perf_balance).to eq(-30_000)

    earn(10_000) # partial: net -200 → still owed nothing to them
    expect(settle_run(10_000)).to be_nil # they're still net-negative; pay nothing

    earn(40_000) # now net +200
    expect(settle_run(40_000).amount_cents).to eq(20_000) # $500 earned - $300 advance
  end

  it "never re-settles or destroys a PAID item (protects payout history)" do
    result = issue_advance(5_000)
    pay!(result.batch)
    item = result.batch.items.find_by(payee: person)
    expect(item.amount_cents).to eq(5_000)
    expect(perf_balance).to eq(-5_000)

    # Simulate a later recalc/detach destroying the contribution on a paid item.
    PayoutContribution.where(source: result.advance).first.destroy!

    expect(item.reload.amount_cents).to eq(5_000)   # amount preserved
    expect(item).to be_paid                          # still paid
    expect(perf_balance).to eq(-5_000)               # payout ledger entry intact
  end

  it "leaves no negative balance and an unpaid advance when the transfer fails" do
    result = issue_advance(5_000)
    allow(Stripe::Transfer).to receive(:create).and_raise(Stripe::StripeError.new("bank rejected"))
    PayoutBatchService.process!(result.batch)

    expect(result.batch.items.first.reload.status).to eq("failed")
    expect(perf_balance).to eq(0)                # no money moved, no negative
    expect(result.advance.reload).not_to be_paid # not marked paid
  end

  it "keeps performer and staff balances from crossing between runs" do
    earn(20_000, category: "performer")
    earn(5_000, category: "staffing")

    expect(settle_run(20_000).amount_cents).to eq(20_000) # only performer earnings, not the $50 staff
  end

  it "still recoups a LEGACY advance entry (pre-rebuild history) against new earnings" do
    # An old paid advance left a negative `advance` entry on the ledger.
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "advance",
                            amount_cents: -5_000, category: "performer", description: "legacy advance")
    earn(12_000)

    expect(settle_run(12_000).amount_cents).to eq(7_000) # $120 earned - $50 legacy advance
  end
end
