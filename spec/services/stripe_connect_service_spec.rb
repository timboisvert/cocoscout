# frozen_string_literal: true

require "rails_helper"

RSpec.describe StripeConnectService do
  let(:person) { create(:person, email: "worker@example.com") }

  def stripe_account(id: "acct_123", payouts_enabled: false, disabled_reason: nil)
    reqs = double("requirements", disabled_reason: disabled_reason)
    double("account", id: id, payouts_enabled: payouts_enabled, requirements: reqs)
  end

  describe "#ensure_account" do
    it "creates an Express account and stores its id" do
      allow(Stripe::Account).to receive(:create).and_return(stripe_account(id: "acct_new"))
      StripeConnectService.new(person).ensure_account
      expect(person.reload.stripe_account_id).to eq("acct_new")
      expect(person.stripe_account_status).to eq("pending")
    end

    it "is idempotent when an account already exists" do
      person.update!(stripe_account_id: "acct_existing")
      expect(Stripe::Account).not_to receive(:create)
      StripeConnectService.new(person).ensure_account
      expect(person.reload.stripe_account_id).to eq("acct_existing")
    end
  end

  describe "#onboarding_link" do
    it "ensures an account and returns a hosted onboarding URL" do
      allow(Stripe::Account).to receive(:create).and_return(stripe_account(id: "acct_x"))
      allow(Stripe::AccountLink).to receive(:create).and_return(double("link", url: "https://connect.stripe.com/setup/x"))
      url = StripeConnectService.new(person).onboarding_link(return_url: "https://app/return", refresh_url: "https://app/refresh")
      expect(url).to eq("https://connect.stripe.com/setup/x")
      expect(person.reload.stripe_account_id).to eq("acct_x")
    end
  end

  describe "#sync_account" do
    before { person.update!(stripe_account_id: "acct_123") }

    it "marks payouts enabled when Stripe says so" do
      StripeConnectService.new(person).sync_account(stripe_account(payouts_enabled: true))
      expect(person.reload.payouts_enabled).to be(true)
      expect(person.stripe_account_status).to eq("enabled")
      expect(person.can_receive_payouts?).to be(true)
    end

    it "marks restricted when there is a disabled reason" do
      StripeConnectService.new(person).sync_account(stripe_account(payouts_enabled: false, disabled_reason: "requirements.past_due"))
      expect(person.reload.payouts_enabled).to be(false)
      expect(person.stripe_account_status).to eq("restricted")
      expect(person.needs_bank_connection?).to be(true)
    end

    it "fetches from Stripe when no account object is passed" do
      allow(Stripe::Account).to receive(:retrieve).with("acct_123").and_return(stripe_account(payouts_enabled: true))
      StripeConnectService.new(person).sync_account
      expect(person.reload.payouts_enabled).to be(true)
    end
  end

  describe ".payee_for_account" do
    it "finds a person by connect account id" do
      person.update!(stripe_account_id: "acct_abc")
      expect(StripeConnectService.payee_for_account("acct_abc")).to eq(person)
    end

    it "finds a contractor by connect account id" do
      org = create(:organization)
      contractor = org.contractors.create!(name: "Sound Co", stripe_account_id: "acct_con")
      expect(StripeConnectService.payee_for_account("acct_con")).to eq(contractor)
    end
  end
end
