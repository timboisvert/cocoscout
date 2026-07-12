# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledPayoutService do
  let(:owner) { create(:user) }
  let!(:org) do
    create(:organization, :pro, owner: owner, stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account",
           payout_schedule: "weekly", payout_schedule_day: Date.current.wday, payout_funding_method: "ach")
  end

  def payee_with_balance(cents)
    person = create(:person, stripe_account_id: "acct_x", payouts_enabled: true)
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "earning", amount_cents: cents)
    person
  end

  it "runs the payout when due and records the day" do
    payee_with_balance(4000)
    allow(Stripe::PaymentIntent).to receive(:create).and_return(double(id: "pi_1", status: "succeeded"))
    allow(Stripe::Transfer).to receive(:create).and_return(double(id: "tr_1"))

    result = nil
    expect { result = described_class.run_due!(org) }.to change(PayoutBatch, :count).by(1)
    expect(result.ran).to be(true)
    expect(result.batch.trigger).to eq("scheduled")
    expect(org.reload.last_auto_payout_on).to eq(Date.current)
  end

  it "does nothing on a non-scheduled day" do
    org.update!(payout_schedule_day: (Date.current.wday + 1) % 7)
    expect { described_class.run_due!(org) }.not_to change(PayoutBatch, :count)
    expect(described_class.run_due!(org).reason).to eq(:not_due)
  end

  it "doesn't double-run once it's run today" do
    org.update!(last_auto_payout_on: Date.current)
    expect(described_class.run_due!(org).reason).to eq(:not_due)
  end

  it "skips (and marks the day) when nobody has a payable balance" do
    result = described_class.run_due!(org)
    expect(result.ran).to be(false)
    expect(result.reason).to eq(:nothing_to_pay)
    expect(org.reload.last_auto_payout_on).to eq(Date.current)
  end
end
