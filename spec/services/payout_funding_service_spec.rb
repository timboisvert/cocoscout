# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutFundingService do
  let(:org) { create(:organization, stripe_customer_id: "cus_1") }

  describe "#setup_session_url" do
    it "creates a bank-only setup-mode checkout session and returns its url" do
      expect(Stripe::Checkout::Session).to receive(:create).with(
        hash_including(mode: "setup", customer: "cus_1", payment_method_types: %w[us_bank_account])
      ).and_return(double(url: "https://checkout.stripe.com/x"))

      url = described_class.new(org).setup_session_url(success_url: "http://s", cancel_url: "http://c")
      expect(url).to eq("https://checkout.stripe.com/x")
    end

    it "creates a Stripe customer first when the org doesn't have one" do
      org.update!(stripe_customer_id: nil)
      allow(Stripe::Customer).to receive(:create).and_return(double(id: "cus_new"))
      allow(Stripe::Checkout::Session).to receive(:create).and_return(double(url: "u"))

      described_class.new(org).setup_session_url(success_url: "s", cancel_url: "c")
      expect(org.reload.stripe_customer_id).to eq("cus_new")
    end
  end

  describe "#save_from_session!" do
    it "stores the bank as the funding source + customer default" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(double(setup_intent: double(payment_method: "pm_9")))
      allow(Stripe::PaymentMethod).to receive(:retrieve).with("pm_9")
        .and_return(double(type: "us_bank_account", us_bank_account: double(bank_name: "Chase", last4: "6789")))
      expect(Stripe::Customer).to receive(:update).with("cus_1", invoice_settings: { default_payment_method: "pm_9" })

      described_class.new(org).save_from_session!("cs_1")
      org.reload
      expect(org.funding_payment_method_id).to eq("pm_9")
      expect(org.funding_payment_method_type).to eq("us_bank_account")
      expect(org.funding_payment_method_label).to eq("Chase •••• 6789")
    end

    it "raises when Checkout returned no payment method" do
      allow(Stripe::Checkout::Session).to receive(:retrieve).and_return(double(setup_intent: double(payment_method: nil)))
      expect { described_class.new(org).save_from_session!("cs_1") }
        .to raise_error(PayoutFundingService::Error, /No payment method/)
    end
  end

  describe "#remove!" do
    it "clears the funding source" do
      org.update!(funding_payment_method_id: "pm_1", funding_payment_method_type: "card", funding_payment_method_label: "Visa •••• 1")
      described_class.new(org).remove!
      expect(org.reload.funding_payment_method_id).to be_nil
    end
  end

  describe "PayoutBatchService.fund! without a source" do
    it "raises a clear error" do
      org.update!(funding_payment_method_id: nil)
      batch = org.payout_batches.create!(trigger: "manual", status: "draft", total_cents: 5000)
      expect { PayoutBatchService.fund!(batch) }.to raise_error(PayoutBatchService::Error, /Connect a bank or card/)
    end
  end
end
