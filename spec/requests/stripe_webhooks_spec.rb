# frozen_string_literal: true

require "rails_helper"

# The money-moving webhook handlers. There were no webhook specs at all before
# this: a bank rejecting a deposit produced no signal anywhere in the app.
RSpec.describe "StripeWebhooksController", type: :request do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, owner: owner) }
  let(:payee) { create(:person, name: "Sam Staffer", stripe_account_id: "acct_123", payouts_enabled: true) }

  let(:batch) do
    org.payout_batches.create!(kind: "performer", status: "completed", trigger: "manual",
                               funding_status: "succeeded", total_cents: 5_000, completed_at: Time.current)
  end
  let!(:item) do
    batch.items.create!(payee: payee, amount_cents: 5_000, status: "pending").tap do |i|
      # Through the real path, so the payout ledger entry exists to be reversed.
      i.mark_paid!(transfer_id: "tr_123")
      i.update!(paid_at: 3.days.ago)
    end
  end

  # Drive the controller the way Stripe does, skipping only signature checks.
  def deliver(type, object, account: nil, id: "evt_#{SecureRandom.hex(6)}")
    event = Stripe::Event.construct_from(
      id: id, type: type, account: account, data: { object: object }
    )
    # construct_event is stubbed, but the controller only calls it once per
    # configured secret — and a fresh checkout (no .env, no master.key) has
    # none, so verification would never even be attempted. Supply one.
    allow_any_instance_of(StripeWebhooksController).to receive(:webhook_secrets).and_return([ "whsec_test" ])
    allow(Stripe::Webhook).to receive(:construct_event).and_return(event)
    post "/webhooks/stripe", params: "{}", headers: { "HTTP_STRIPE_SIGNATURE" => "sig" }
  end

  describe "payout.failed — the payee's bank rejected the deposit" do
    let(:payout) { Stripe::Payout.construct_from(id: "po_1", amount: 5_000, failure_message: "Account closed") }

    it "returns the money, reverses the ledger and reopens the run" do
      deliver("payout.failed", payout, account: "acct_123")

      expect(item.reload.status).to eq("returned")
      expect(item.error).to include("Account closed")
      # The payout entry stays — the payment happened — and a reversal restores
      # the balance beside it, so both halves of the story survive.
      entries = PayoutLedgerEntry.where(source: item)
      expect(entries.pluck(:entry_type)).to contain_exactly("payout", "reversal")
      expect(entries.sum(:amount_cents)).to eq(0)
      expect(batch.reload.status).to eq("partially_paid")
      expect(batch.completed_at).to be_nil
    end

    it "tells the payee and the org" do
      expect { deliver("payout.failed", payout, account: "acct_123") }
        .to change { ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "PayoutReturnedNotificationJob" } }.by(1)
    end

    it "refuses to guess when the amount matches more than one payment" do
      batch.items.create!(payee: payee, amount_cents: 5_000, status: "paid", paid_at: 1.day.ago)

      deliver("payout.failed", payout, account: "acct_123")

      expect(item.reload.status).to eq("paid")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |j| j["job_class"] })
        .to include("PayoutAccountProblemNotificationJob")
    end

    it "ignores an account we don't know" do
      deliver("payout.failed", payout, account: "acct_nope")
      expect(item.reload.status).to eq("paid")
    end
  end

  describe "transfer.reversed" do
    it "routes through the same return path and recomputes the run" do
      deliver("transfer.reversed", Stripe::Transfer.construct_from(id: "tr_123", amount: 5_000))

      expect(item.reload.status).to eq("returned")
      expect(batch.reload.status).to eq("partially_paid")
    end
  end

  describe "redelivery" do
    it "does the work once, however many times Stripe sends it" do
      payout = Stripe::Payout.construct_from(id: "po_1", amount: 5_000, failure_message: "Account closed")
      deliver("payout.failed", payout, account: "acct_123", id: "evt_same")
      deliver("payout.failed", payout, account: "acct_123", id: "evt_same")

      expect(PayoutLedgerEntry.where(source: item, entry_type: "reversal").count).to eq(1)
    end
  end

  describe "payment_intent.payment_failed — the funding debit bounced" do
    it "marks the run failed and tells somebody" do
      funding = org.payout_batches.create!(kind: "staff_pay", status: "funding", trigger: "manual",
                                           funding_payment_intent_id: "pi_1", total_cents: 1_000)

      expect { deliver("payment_intent.payment_failed", Stripe::PaymentIntent.construct_from(id: "pi_1")) }
        .to change { ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "PayoutFundingFailedNotificationJob" } }.by(1)

      expect(funding.reload.status).to eq("failed")
    end
  end

  describe "account.updated" do
    it "chases the money waiting on that person the moment they connect" do
      expect { deliver("account.updated", Stripe::Account.construct_from(id: "acct_123", payouts_enabled: true)) }
        .to change { ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "RetryParkedPayoutsJob" } }.by(1)
    end
  end
end
