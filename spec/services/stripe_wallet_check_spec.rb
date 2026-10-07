# frozen_string_literal: true

require "rails_helper"

# bin/rails stripe:wallets: where Apple Pay, Google Pay and the rest stand on
# CocoScout's Stripe account, from Stripe's own answers (stubbed here).
RSpec.describe StripeWalletCheck do
  def list(objects, url)
    Stripe::ListObject.construct_from(object: "list", data: objects, has_more: false, url: url)
  end

  def domain(name, apple: "active", google: "active", error: nil)
    Stripe::PaymentMethodDomain.construct_from(
      id: "pmd_#{name.tr('.', '_')}", object: "payment_method_domain", domain_name: name, enabled: true,
      apple_pay: { status: apple, status_details: (error ? { error_message: error } : nil) },
      google_pay: { status: google }, link: { status: "active" }
    )
  end

  let(:config) do
    Stripe::PaymentMethodConfiguration.construct_from(
      id: "pmc_1", object: "payment_method_configuration", name: "Default", is_default: true,
      card: { available: true }, apple_pay: { available: true }, google_pay: { available: false },
      link: { available: true }, klarna: { available: true }, pix: { available: true }, us_bank_account: { available: false }
    )
  end

  let(:charges) do
    [
      Stripe::Charge.construct_from(id: "ch_1", paid: true, payment_method_details: { type: "card", card: { wallet: { type: "apple_pay" } } }),
      Stripe::Charge.construct_from(id: "ch_2", paid: true, payment_method_details: { type: "card", card: { wallet: nil } }),
      Stripe::Charge.construct_from(id: "ch_3", paid: true, payment_method_details: { type: "link" }),
      Stripe::Charge.construct_from(id: "ch_4", paid: false, payment_method_details: { type: "card", card: { wallet: nil } })
    ]
  end

  it "says which domains are registered, what checkout offers, and how people paid" do
    allow(Stripe::PaymentMethodDomain).to receive(:list).and_return(list([ domain("cocoscout.com", apple: "inactive", error: "Domain not verified") ], "/v1/payment_method_domains"))
    allow(Stripe::PaymentMethodConfiguration).to receive(:list).and_return(list([ config ], "/v1/payment_method_configurations"))
    allow(Stripe::Charge).to receive(:list).and_return(list(charges, "/v1/charges"))

    out = StringIO.new
    described_class.report(out)
    text = out.string

    expect(text).to include("cocoscout.com: apple pay inactive (Domain not verified), google pay active, link active")
    expect(text).to include("www.cocoscout.com: NOT REGISTERED")
    expect(text).to include("google pay: OFF, turn it on", "card: on")
    expect(text).to include("klarna: on, and US buyers can see it. Turn it off: about 6% plus 30¢")
    expect(text).to include("never shown for US dollar payments: pix")
    expect(text).to include("card via apple pay: 1", "card: 1", "link: 1")
  end

  it "registers the domains that aren't yet, and re-checks the ones that are" do
    allow(Stripe::PaymentMethodDomain).to receive(:list).and_return(list([ domain("cocoscout.com") ], "/v1/payment_method_domains"))
    allow(Stripe::PaymentMethodDomain).to receive(:create).with(domain_name: "www.cocoscout.com").and_return(domain("www.cocoscout.com"))
    allow(Stripe::PaymentMethodDomain).to receive(:validate) { |id| domain(id.delete_prefix("pmd_").tr("_", ".")) }

    out = StringIO.new
    described_class.register!(out)

    expect(Stripe::PaymentMethodDomain).to have_received(:create).once
    expect(out.string).to include("Already registered cocoscout.com: apple pay active", "Registered www.cocoscout.com: apple pay active")
  end
end
