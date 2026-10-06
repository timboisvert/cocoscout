# frozen_string_literal: true

require "rails_helper"

# The money-moving webhook handlers. There were no webhook specs at all before
# this: a bank rejecting a deposit produced no signal anywhere in the app.
RSpec.describe "StripeWebhooksController", type: :request do
  include ActiveJob::TestHelper

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

  # Which transfers a connected account's payout carried is read from Stripe;
  # by default Stripe can't be asked, so the old match by amount applies.
  before { allow(ConnectPayoutTracker).to receive(:transfer_ids).and_return(nil) }

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

  describe "payout.failed — read exactly from the payout's transfers" do
    it "returns only the items the payout carried, even when another shares the amount" do
      twin = batch.items.create!(payee: payee, amount_cents: 5_000, status: "pending").tap { |i| i.mark_paid!(transfer_id: "tr_twin") }
      allow(ConnectPayoutTracker).to receive(:transfer_ids).with("po_1", "acct_123").and_return([ "tr_twin" ])

      deliver("payout.failed", Stripe::Payout.construct_from(id: "po_1", amount: 5_000, failure_message: "Account closed"), account: "acct_123")

      expect(twin.reload.status).to eq("returned")
      expect(item.reload.status).to eq("paid")
    end
  end

  describe "a theater's withdrawal, followed to its bank" do
    let(:theater) { create(:organization, stripe_account_id: "acct_theater", payouts_enabled: true) }
    let!(:withdrawal) do
      theater.balance_withdrawals.create!(amount_cents: 200_000, status: "sent", stripe_transfer_id: "tr_w").tap do |w|
        OrgCashEntry.post!(organization: theater, entry_type: "transfer", amount_cents: -200_000, source: w, description: "Withdrawal to your bank")
      end
    end

    it "says when it reached their bank" do
      allow(ConnectPayoutTracker).to receive(:transfer_ids).with("po_w", "acct_theater").and_return([ "tr_w" ])
      deliver("payout.paid", Stripe::Payout.construct_from(id: "po_w", amount: 200_000), account: "acct_theater")
      expect(withdrawal.reload.attributes.slice("status", "stripe_payout_id")).to eq("status" => "paid", "stripe_payout_id" => "po_w")
      expect(withdrawal.paid_at).to be_present
    end

    it "says when their bank turned it down, and never guesses a run item by amount on a theater's account" do
      theater_item = batch.items.create!(payee: theater, amount_cents: 200_000, status: "pending").tap { |i| i.mark_paid!(transfer_id: "tr_remit") }
      allow(ConnectPayoutTracker).to receive(:transfer_ids).with("po_w", "acct_theater").and_return([ "tr_w" ])
      deliver("payout.failed", Stripe::Payout.construct_from(id: "po_w", amount: 200_000, failure_message: "Account closed"), account: "acct_theater")

      expect(withdrawal.reload.status).to eq("bank_rejected")
      expect(withdrawal.error).to include("Account closed")
      expect(theater_item.reload.status).to eq("paid")
      expect(OrgCashEntry.balance_cents(theater)).to eq(-200_000)
    end

    it "gives the money back to the theater's balance when the transfer is reversed" do
      deliver("transfer.reversed", Stripe::Transfer.construct_from(id: "tr_w", amount: 200_000))
      expect(withdrawal.reload.status).to eq("reversed")
      expect(OrgCashEntry.balance_cents(theater)).to eq(0)
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
      allow_any_instance_of(CourseRegistration).to receive(:record_stripe_fee!)

      session = Stripe::Checkout::Session.construct_from(
        id: "cs_1", payment_intent: "pi_course",
        metadata: { "course_offering_id" => offering.id.to_s, "person_id" => student.id.to_s,
                    "amount_cents" => "4000", "tax_cents" => "410", "currency" => "usd" }
      )
      TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "10.25", mode: "added")
      deliver("checkout.session.completed", session)

      registration = CourseRegistration.find_by(stripe_checkout_session_id: "cs_1")
      entry = OrgCashEntry.find_by(source: registration, entry_type: "course_registration")
      # Net of the 10% platform fee on the price, plus the tax collected for the org.
      expect(entry.organization).to eq(org)
      expect(registration.tax_cents).to eq(410)
      expect(entry.amount_cents).to eq(3_600 + 410)
      expect(registration.tax_lines.sole.tax_cents).to eq(410)

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

  describe "a handler that fails" do
    it "answers 500 and lets Stripe's next delivery do the work" do
      payout = Stripe::Payout.construct_from(id: "po_1", amount: 5_000, failure_message: "Account closed")
      calls = 0
      allow(PayoutBatchService).to receive(:return_item!).and_wrap_original do |original, *args, **kwargs|
        calls += 1
        raise ActiveRecord::Deadlocked, "deadlock" if calls == 1

        original.call(*args, **kwargs)
      end

      deliver("payout.failed", payout, account: "acct_123", id: "evt_retry")
      expect(response).to have_http_status(:internal_server_error)
      expect(WebhookEvent.find_by(event_id: "evt_retry").attributes.slice("status", "attempts")).to eq("status" => "failed", "attempts" => 1)
      expect(item.reload.status).to eq("paid")

      deliver("payout.failed", payout, account: "acct_123", id: "evt_retry")
      expect(response).to have_http_status(:ok)
      expect(item.reload.status).to eq("returned")
      expect(WebhookEvent.find_by(event_id: "evt_retry").attributes.slice("status", "attempts")).to eq("status" => "processed", "attempts" => 2)

      deliver("payout.failed", payout, account: "acct_123", id: "evt_retry")
      expect(calls).to eq(2)
    end
  end

  describe "subscriptions and invoices" do
    it "ignores the usage subscription's events for Pro" do
      org.update!(stripe_subscription_id: "sub_pro", subscription_status: "canceled", staffing_subscription_id: "sub_usage")
      usage = Stripe::Subscription.construct_from(id: "sub_usage", customer: "cus_1", status: "active",
                                                  metadata: { kind: "staffing", organization_id: org.id.to_s }, items: { data: [] })
      deliver("customer.subscription.updated", usage)
      expect(org.reload.attributes.slice("stripe_subscription_id", "subscription_status"))
        .to eq("stripe_subscription_id" => "sub_pro", "subscription_status" => "canceled")
    end

    it "finds an invoice's subscription in the newer API's place, and skips usage invoices" do
      org.update!(stripe_subscription_id: "sub_pro", staffing_subscription_id: "sub_usage", stripe_customer_id: "cus_1")
      expect(SubscriptionSyncService).to receive(:from_id).with(org, "sub_pro").once
      deliver("invoice.paid", Stripe::Invoice.construct_from(id: "in_1", customer: "cus_1",
                                                              parent: { subscription_details: { subscription: "sub_pro" } }))
      deliver("invoice.paid", Stripe::Invoice.construct_from(id: "in_2", customer: "cus_1",
                                                              parent: { subscription_details: { subscription: "sub_usage" } }))
    end
  end

  describe "a usage bill Stripe just drafted" do
    it "is corrected to the people CocoScout paid that month, before Stripe charges it" do
      org.update!(stripe_customer_id: "cus_sg", staffing_subscription_id: "sub_usage")
      month = Date.new(2026, 10, 1)
      3.times { StaffActivation.record!(organization: org, person: create(:person), month: month) }
      7.times { PerformerActivation.record!(organization: org, person: create(:person), month: month) }
      draft = Stripe::Invoice.construct_from(
        id: "in_oct", object: "invoice", customer: "cus_sg", status: "draft", amount_due: 8_100, amount_paid: 0, amount_remaining: 8_100,
        period_start: Time.zone.local(2026, 9, 30).to_i, period_end: Time.zone.local(2026, 10, 30).to_i,
        parent: { subscription_details: { subscription: "sub_usage" } },
        lines: { data: [ { description: "12 × active staff member", quantity: 12, amount: 6_000 },
                         { description: "7 × active performer", quantity: 7, amount: 2_100 } ] }
      )
      expect(Stripe::InvoiceItem).to receive(:create)
        .with(hash_including(customer: "cus_sg", invoice: "in_oct", amount: -4_500, description: a_string_including("3 staff and 7 performers", "October 2026")),
              hash_including(idempotency_key: "usage-correction-in_oct--4500"))
      deliver("invoice.created", draft)
      expect(response).to have_http_status(:ok)
      expect(BillingInvoice.find_by(stripe_invoice_id: "in_oct").kind).to eq("usage")
    end

    it "leaves a bill that already matches alone" do
      org.update!(stripe_customer_id: "cus_sg", staffing_subscription_id: "sub_usage")
      StaffActivation.record!(organization: org, person: create(:person), month: Date.new(2026, 10, 1))
      draft = Stripe::Invoice.construct_from(
        id: "in_ok", object: "invoice", customer: "cus_sg", status: "draft", amount_due: 500,
        period_start: Time.zone.local(2026, 10, 1).to_i, period_end: Time.zone.local(2026, 11, 1).to_i,
        parent: { subscription_details: { subscription: "sub_usage" } },
        lines: { data: [ { description: "1 × active staff member", quantity: 1, amount: 500 } ] }
      )
      expect(Stripe::InvoiceItem).not_to receive(:create)
      deliver("invoice.created", draft)
    end
  end

  describe "bill emails" do
    it "emails the owner the bill when Stripe issues it, and a receipt when it's paid, once each" do
      org.update!(stripe_customer_id: "cus_sg", staffing_subscription_id: "sub_usage")
      base = { id: "in_sep", object: "invoice", customer: "cus_sg", amount_due: 4_100, amount_remaining: 4_100, number: "SG-0009",
               period_start: Time.zone.local(2026, 9, 1).to_i, period_end: Time.zone.local(2026, 10, 1).to_i,
               hosted_invoice_url: "https://invoice.stripe.com/i/x", parent: { subscription_details: { subscription: "sub_usage" } },
               lines: { data: [ { description: "7 × active staff member", quantity: 7, amount: 3_500 }, { description: "2 × active performer", quantity: 2, amount: 600 } ] } }
      expect {
        perform_enqueued_jobs { deliver("invoice.finalized", Stripe::Invoice.construct_from(base.merge(status: "open", amount_paid: 0))) }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ owner.email_address ])
      expect(mail.subject).to eq("Your CocoScout bill: September 2026 usage, $41.00")
      # CocoScout's own invoice, attached and linked; never Stripe's page.
      expect(mail.html_part&.body&.to_s || mail.body.to_s).to include("7 × active staff member: $35.00", "/manage/billing/invoices/")
      expect(mail.html_part&.body&.to_s || mail.body.to_s).not_to include("invoice.stripe.com")
      expect(mail.attachments.reject(&:inline?).map(&:filename)).to eq([ "CocoScout invoice SG-0009 (September 2026 usage).pdf" ])

      allow(Stripe::Invoice).to receive(:retrieve).and_return(Stripe::Invoice.construct_from(base.merge(status: "paid", amount_paid: 4_100, amount_remaining: 0,
                                                                                                         status_transitions: { paid_at: Time.zone.local(2026, 10, 4).to_i })))
      expect {
        perform_enqueued_jobs { 2.times { deliver("invoice.paid", Stripe::Invoice.construct_from(base.merge(status: "paid"))) } }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(ActionMailer::Base.deliveries.last.subject).to eq("Receipt: September 2026 usage, $41.00 paid")
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
  describe "ticket orders" do
    let(:listing) { create(:ticket_listing, organization: org) }
    let!(:tier) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }
    let(:order) { TicketCheckout.start!(listing: listing, quantities: { tier.id.to_s => "2" }) }

    def intent
      Stripe::PaymentIntent.construct_from(id: "pi_tix", amount: order.total_cents, latest_charge: "ch_tix",
                                           metadata: { type: "ticket_order", ticket_order_id: order.id.to_s })
    end

    it "settles a paid order once, however many times Stripe delivers it" do
      deliver("payment_intent.succeeded", intent, id: "evt_tix")
      deliver("payment_intent.succeeded", intent, id: "evt_tix")
      deliver("payment_intent.succeeded", intent, id: "evt_tix_retry")

      expect([ order.reload.status, order.stripe_charge_id ]).to eq([ "paid", "ch_tix" ])
      expect(OrgCashEntry.where(source: order).count).to eq(1)
      expect(JournalEntry.live.where(source: order).count).to eq(1)
    end

    it "takes a disputed charge out of the theater's money, and gives it back on a win" do
      deliver("payment_intent.succeeded", intent)
      dispute = ->(status) { Stripe::Dispute.construct_from(id: "dp_1", payment_intent: "pi_tix", charge: "ch_tix", amount: order.total_cents, status: status) }

      deliver("charge.dispute.created", dispute.call("needs_response"))
      expect(OrgCashEntry.where(source: order, entry_type: "ticket_dispute").sum(:amount_cents)).to eq(-(order.total_cents + 1_500))

      deliver("charge.dispute.closed", dispute.call("won"))
      expect(OrgCashEntry.where(source: order, entry_type: "ticket_dispute")).to be_empty
    end
  end
end
