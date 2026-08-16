# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseRegistrationRefundService do
  let(:org) { create(:organization, :pro, owner: create(:user)) }
  let(:production) { create(:production, organization: org, production_type: "course") }
  let(:offering) { create(:course_offering, production: production, price_cents: 5000) }

  before { allow(Stripe).to receive(:api_key).and_return("sk_test_x") }

  it "refunds through Stripe, marks the registration refunded, and keeps the refund id" do
    registration = create(:course_registration, course_offering: offering, amount_cents: 5000, cocoscout_fee_cents: 500,
                                                status: "confirmed", stripe_payment_intent_id: "pi_1")
    allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_1"))

    result = described_class.call(registration)

    expect(result).to be_ok
    expect(Stripe::Refund).to have_received(:create).with(hash_including(payment_intent: "pi_1"))
    expect(registration.reload).to have_attributes(status: "refunded", stripe_refund_id: "re_1")
    expect(registration.refunded_at).to be_present
  end

  it "posts the refund on the org's cash ledger" do
    registration = create(:course_registration, course_offering: offering, amount_cents: 5000, cocoscout_fee_cents: 500,
                                                status: "confirmed", stripe_payment_intent_id: "pi_1")
    allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_1"))

    described_class.call(registration)

    expect(OrgCashEntry.where(source: registration, entry_type: "refund").sum(:amount_cents)).to eq(-4500)
  end

  it "releases the ledger reservation and reports the error when Stripe refuses" do
    registration = create(:course_registration, course_offering: offering, amount_cents: 5000, cocoscout_fee_cents: 500,
                                                status: "confirmed", stripe_payment_intent_id: "pi_1")
    allow(Stripe::Refund).to receive(:create).and_raise(Stripe::StripeError.new("charge already refunded"))

    result = described_class.call(registration)

    expect(result).not_to be_ok
    expect(result.error).to include("charge already refunded")
    expect(registration.reload).to be_confirmed
    expect(OrgCashEntry.where(source: registration, entry_type: "refund")).to be_empty
  end

  it "just marks a registration that was never charged" do
    registration = create(:course_registration, course_offering: offering, amount_cents: 0, status: "confirmed",
                                                stripe_payment_intent_id: nil)
    allow(Stripe::Refund).to receive(:create)

    result = described_class.call(registration)

    expect(result).to be_ok
    expect(Stripe::Refund).not_to have_received(:create)
    expect(registration.reload).to be_refunded
  end

  it "refuses anything that isn't confirmed" do
    registration = create(:course_registration, course_offering: offering, status: "refunded")
    result = described_class.call(registration)
    expect(result).not_to be_ok
    expect(result.error).to include("Only confirmed")
  end
end
