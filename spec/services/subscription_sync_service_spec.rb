# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe SubscriptionSyncService, type: :service do
  let(:organization) { create(:organization) }

  # Minimal stand-in for a Stripe::Subscription (supports both .attr and ["attr"]).
  def stripe_subscription(status:, interval: "month", period_end: 30.days.from_now.to_i,
                          canceled_at: nil, id: "sub_abc", customer: "cus_abc")
    item = OpenStruct.new(price: OpenStruct.new(recurring: OpenStruct.new(interval: interval)))
    OpenStruct.new(
      id: id, customer: customer, status: status,
      items: OpenStruct.new(data: [ item ]),
      current_period_end: period_end,
      canceled_at: canceled_at
    )
  end

  it "moves the org onto the paid tier for an active subscription" do
    sub = stripe_subscription(status: "active", interval: "year")

    described_class.new(organization, sub).call
    organization.reload

    expect(organization.subscription_tier).to eq("paid")
    expect(organization.subscription_status).to eq("active")
    expect(organization.subscription_interval).to eq("year")
    expect(organization.stripe_subscription_id).to eq("sub_abc")
    expect(organization.stripe_customer_id).to eq("cus_abc")
    expect(organization.on_paid_plan?).to be true
  end

  it "returns the org to free when the subscription is canceled" do
    organization.update!(subscription_tier: "paid", subscription_status: "active", stripe_subscription_id: "sub_abc")
    sub = stripe_subscription(status: "canceled", canceled_at: Time.current.to_i)

    described_class.new(organization, sub).call
    organization.reload

    expect(organization.subscription_tier).to eq("free")
    expect(organization.subscription_status).to eq("canceled")
    expect(organization.subscription_canceled_at).to be_present
    expect(organization.on_paid_plan?).to be false
  end

  it "keeps past_due orgs on the paid tier" do
    described_class.new(organization, stripe_subscription(status: "past_due")).call
    expect(organization.reload.on_paid_plan?).to be true
  end
end
