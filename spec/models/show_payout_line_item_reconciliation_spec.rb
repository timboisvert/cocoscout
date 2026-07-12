# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ShowPayoutLineItem payout-run reconciliation" do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }
  let(:show_payout) { create(:show_payout, show: show) }
  let(:payee) { create(:person, name: "Bank Bea", stripe_account_id: "acct_x", payouts_enabled: true) }
  let(:item) { create(:show_payout_line_item, show_payout: show_payout, payee: payee, amount: 50.0) }

  # Each earning comes from a distinct source (a different show), so they
  # accumulate rather than upsert over each other.
  def earn(cents, source: create(:show, production: production))
    PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: cents, source: source)
  end

  it "shows auto-pay (pending) when bank-connected with an outstanding balance" do
    earn(5000)
    expect(item.auto_payout?).to be(true)
    expect(item.settled_via_payout_run?).to be(false)
  end

  it "flips to 'settled via payout run' once a completed batch pays their balance down" do
    earn(5000)
    batch = org.payout_batches.create!(trigger: "manual", status: "completed", kind: "staff_pay")
    batch.items.create!(payee: payee, amount_cents: 5000, status: "pending").mark_paid!(transfer_id: "tr_1")

    expect(org.payout_balance_cents_for(payee)).to eq(0)
    expect(item.settled_via_payout_run?).to be(true)
    expect(item.auto_payout?).to be(false)
  end

  it "goes back to auto-pay when new earnings leave an outstanding balance again" do
    earn(5000)
    batch = org.payout_batches.create!(trigger: "manual", status: "completed", kind: "staff_pay")
    batch.items.create!(payee: payee, amount_cents: 5000, status: "pending").mark_paid!(transfer_id: "tr_1")
    earn(3000) # a later show; now they're owed again

    expect(item.settled_via_payout_run?).to be(false)
    expect(item.auto_payout?).to be(true)
  end

  it "is neither for a legacy performer without a connected bank" do
    legacy = create(:person, name: "Legacy Lou")
    li = create(:show_payout_line_item, show_payout: show_payout, payee: legacy, amount: 50.0)
    expect(li.auto_payout?).to be(false)
    expect(li.settled_via_payout_run?).to be(false)
  end
end
