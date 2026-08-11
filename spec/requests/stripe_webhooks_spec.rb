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

    it "credits the org's cash ledger — the money is back in OUR balance" do
      deliver("transfer.reversed", Stripe::Transfer.construct_from(id: "tr_123", amount: 5_000))

      entry = OrgCashEntry.find_by(source: item, entry_type: "transfer_reversal")
      expect(entry.organization).to eq(org)
      expect(entry.amount_cents).to eq(5_000)
    end
  end

  describe "payout.failed does NOT credit the cash ledger" do
    it "the money sits in the payee's Connect balance, not ours" do
      payout = Stripe::Payout.construct_from(id: "po_1", amount: 5_000, failure_message: "Account closed")
      deliver("payout.failed", payout, account: "acct_123")

      expect(item.reload.status).to eq("returned")
      expect(OrgCashEntry.where(entry_type: "transfer_reversal")).to be_empty
    end
  end

  describe "checkout.session.completed — course registration" do
    let(:production) { create(:production, organization: org, production_type: "course") }
    let(:offering) { create(:course_offering, production: production, price_cents: 4_000) }
    let(:student) { create(:person) }

    it "posts the org's net share to the cash ledger, restated when the Stripe fee lands" do
      allow_any_instance_of(StripeWebhooksController).to receive(:record_stripe_fee)

      session = Stripe::Checkout::Session.construct_from(
        id: "cs_1", payment_intent: "pi_course",
        metadata: { "course_offering_id" => offering.id.to_s, "person_id" => student.id.to_s,
                    "amount_cents" => "4000", "currency" => "usd" }
      )
      deliver("checkout.session.completed", session)

      registration = CourseRegistration.find_by(stripe_checkout_session_id: "cs_1")
      entry = OrgCashEntry.find_by(source: registration, entry_type: "course_registration")
      # Net of the 10% platform fee.
      expect(entry.organization).to eq(org)
      expect(entry.amount_cents).to eq(3_600)

      # The hourly fee backfill later restates the same row, not a second one.
      registration.update!(stripe_fee_cents: 146)
      expect(OrgCashEntry.where(source: registration, entry_type: "course_registration").count).to eq(1)
    end
  end

  describe "charge.refunded — course registration" do
    let(:production) { create(:production, organization: org, production_type: "course") }
    let(:offering) { create(:course_offering, production: production, price_cents: 4_000) }

    it "debits the org's cash ledger by the same net the credit posted" do
      registration = offering.course_registrations.create!(
        person: create(:person), status: :confirmed, amount_cents: 4_000, currency: "usd",
        registered_at: Time.current, paid_at: Time.current,
        stripe_checkout_session_id: "cs_r", stripe_payment_intent_id: "pi_r",
        cocoscout_fee_cents: 400
      )

      deliver("charge.refunded", Stripe::Charge.construct_from(id: "ch_1", payment_intent: "pi_r"))

      expect(registration.reload.status).to eq("refunded")
      entries = OrgCashEntry.where(source: registration)
      expect(entries.pluck(:entry_type)).to contain_exactly("course_registration", "refund")
      expect(entries.sum(:amount_cents)).to eq(0)
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
