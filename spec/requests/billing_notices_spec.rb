# frozen_string_literal: true

require "rails_helper"

# CocoScout's own failed-payment email and yearly renewal reminder (Tim,
# 2026-11-24): Stripe's subscription emails to organizations are switched
# off, so these are the only word an organization gets.
RSpec.describe "Billing notices", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, email_address: "owner@sg.example") }
  let!(:owner_person) { create(:person, user: owner, name: "Tim Owner") }
  let!(:org) do
    create(:organization, name: "Stars & Garters", owner: owner, stripe_customer_id: "cus_sg", stripe_subscription_id: "sub_pro",
                          time_zone: "Central Time (US & Canada)")
  end
  let(:now) { Time.zone.local(2026, 11, 24, 10) }

  before do
    PlatformTemplates.ensure!(keys: %w[cocoscout_payment_failed cocoscout_pro_renewal cocoscout_bill cocoscout_bill_paid])
    ActionMailer::Base.deliveries.clear
  end

  def body(mail = ActionMailer::Base.deliveries.last) = mail.html_part&.body&.decoded || mail.body.decoded

  describe "a payment that didn't go through" do
    let(:bill) do
      BillingInvoice.create!(organization: org, stripe_invoice_id: "in_fail", kind: "pro", status: "open", number: "SG-0012",
                             amount_due_cents: 29_900, amount_remaining_cents: 29_900,
                             period_start: Time.zone.local(2026, 11, 20), period_end: Time.zone.local(2027, 11, 20),
                             failed_at: now, next_payment_attempt_at: Time.zone.local(2026, 11, 27, 15))
    end

    it "emails the billing contacts the bill, the amount, the next try, and where to fix it" do
      travel_to now do
        BillingInvoiceEmailJob.perform_now(bill.id, "failed")

        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to eq([ "owner@sg.example" ])
        expect(mail.subject).to start_with("Your CocoScout payment didn't go through: ").and end_with("$299.00")
        expect(body).to include("Hi Tim,", "didn't go through", "It will be tried again on November 27.", "/manage/organizations/#{org.id}/section/billing")
        expect(body).not_to match(/stripe/i)
      end
    end

    it "emails once for each failed attempt, however often Stripe repeats one" do
      travel_to now do
        expect { 2.times { BillingInvoiceEmailJob.perform_now(bill.id, "failed") } }.to change { ActionMailer::Base.deliveries.size }.by(1)

        bill.update!(next_payment_attempt_at: Time.zone.local(2026, 12, 2, 15))
        expect { BillingInvoiceEmailJob.perform_now(bill.id, "failed") }.to change { ActionMailer::Base.deliveries.size }.by(1)
        expect(body).to include("It will be tried again on December 2.")
      end
    end

    it "says it won't be tried again after the last attempt, and then stops" do
      travel_to now do
        bill.update!(next_payment_attempt_at: nil)
        expect { 2.times { BillingInvoiceEmailJob.perform_now(bill.id, "failed") } }.to change { ActionMailer::Base.deliveries.size }.by(1)
        expect(body).to include("It won't be tried again, so the bill stays unpaid until you pay it.")
        expect(body).not_to include("tried again on")
      end
    end

    it "sends nothing for a bill that was paid in the meantime" do
      bill.update!(status: "paid", amount_paid_cents: 29_900, paid_at: now)
      expect { BillingInvoiceEmailJob.perform_now(bill.id, "failed") }.not_to(change { ActionMailer::Base.deliveries.size })
    end

    describe "from Stripe's webhook" do
      def deliver(type, object)
        event = Stripe::Event.construct_from(id: "evt_#{SecureRandom.hex(6)}", type: type, account: nil, data: { object: object })
        allow_any_instance_of(StripeWebhooksController).to receive(:webhook_secrets).and_return([ "whsec_test" ])
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event)
        post "/webhooks/stripe", params: "{}", headers: { "HTTP_STRIPE_SIGNATURE" => "sig" }
      end

      def failed_invoice(reason)
        Stripe::Invoice.construct_from(id: "in_hook", object: "invoice", customer: "cus_sg", status: "open", billing_reason: reason,
                                       amount_due: 29_900, amount_paid: 0, amount_remaining: 29_900,
                                       next_payment_attempt: (now + 3.days).to_i,
                                       lines: { data: [ { description: "1 × Pro (at $299.00 / year)", quantity: 1, amount: 29_900 } ] })
      end

      before { allow(SubscriptionSyncService).to receive(:from_id) }

      it "emails when a renewal's payment fails" do
        travel_to now do
          expect { perform_enqueued_jobs { deliver("invoice.payment_failed", failed_invoice("subscription_cycle")) } }
            .to change { ActionMailer::Base.deliveries.size }.by(1)
          expect(response).to have_http_status(:ok)
          expect(ActionMailer::Base.deliveries.last.subject).to start_with("Your CocoScout payment didn't go through")
        end
      end

      it "stays quiet when a new subscription's first payment fails at the checkout" do
        travel_to now do
          expect { perform_enqueued_jobs { deliver("invoice.payment_failed", failed_invoice("subscription_create")) } }
            .not_to(change { ActionMailer::Base.deliveries.size })
        end
      end
    end
  end

  describe "a yearly plan about to renew" do
    let(:renews_at) { Time.zone.local(2026, 12, 20, 9) }

    before do
      org.update!(subscription_interval: "year", subscription_status: "active", subscription_tier: "paid", subscription_current_period_end: renews_at)
      allow(Stripe::Invoice).to receive(:create_preview).and_return(Stripe::Invoice.construct_from(id: "upcoming", amount_due: 29_900))
    end

    it "reminds the billing contacts once, with the day, Stripe's amount, and where to change or cancel" do
      travel_to now do
        expect { 2.times { ProRenewalReminderJob.perform_now } }.to change { ActionMailer::Base.deliveries.size }.by(1)

        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to eq([ "owner@sg.example" ])
        expect(mail.subject).to eq("CocoScout Pro renews on December 20, 2026")
        expect(body).to include("Hi Tim,", "renews on <strong>December 20, 2026</strong> for another year",
                                "$299.00 will be charged to the payment method on file with CocoScout that day.",
                                "Manage subscription", "/manage/organizations/#{org.id}/section/billing")
        expect(body).not_to match(/stripe/i)
        expect(Stripe::Invoice).to have_received(:create_preview).with({ customer: "cus_sg", subscription: "sub_pro" }).once
      end
    end

    it "reminds again for the next year's renewal" do
      travel_to(now) { ProRenewalReminderJob.perform_now }
      org.update!(subscription_current_period_end: renews_at + 1.year)

      travel_to(now + 1.year) do
        expect { ProRenewalReminderJob.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
        expect(ActionMailer::Base.deliveries.last.subject).to eq("CocoScout Pro renews on December 20, 2027")
      end
    end

    it "says nothing is charged when credit covers the renewal" do
      allow(Stripe::Invoice).to receive(:create_preview).and_return(Stripe::Invoice.construct_from(id: "upcoming", amount_due: 0))
      travel_to(now) { ProRenewalReminderJob.perform_now }
      expect(body).to include("Nothing will be charged that day")
    end

    it "waits for tomorrow when Stripe has no renewal to show" do
      allow(Stripe::Invoice).to receive(:create_preview).and_raise(Stripe::InvalidRequestError.new("No upcoming invoices for customer", nil))
      travel_to now do
        expect { ProRenewalReminderJob.perform_now }.not_to(change { ActionMailer::Base.deliveries.size })
        expect(org.reload.renewal_reminded_for).to be_nil
      end
    end

    it "leaves out a plan that isn't renewing in the next 30 days" do
      travel_to now do
        {
          "more than 30 days away" => { subscription_current_period_end: now + 31.days },
          "monthly" => { subscription_interval: "month" },
          "canceled, ending at the period's end" => { subscription_canceled_at: now - 1.day },
          "a trial" => { subscription_status: "trialing" },
          "past due" => { subscription_status: "past_due" }
        }.each do |why, attributes|
          org.update!({ subscription_interval: "year", subscription_status: "active", subscription_canceled_at: nil,
                        subscription_current_period_end: renews_at }.merge(attributes))
          expect(ProRenewalReminder.due.to_a).to eq([]), why
        end
      end
    end
  end
end
