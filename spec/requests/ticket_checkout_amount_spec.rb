# frozen_string_literal: true

require "rails_helper"

# A card payment settles an order only when it paid what the order costs.
# The checkout page can still add products and deals after the
# PaymentIntent is made, so a buyer could confirm the first (smaller) intent
# and walk off with the rest: the order settled at its new total and the
# theater's CocoScout balance was credited money that never arrived.
RSpec.describe "Ticket checkout: the payment must match the order", type: :request do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:show) { create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 19, min: 30)) }
  let(:bottle) { create(:ticket_product, organization: org, name: "Champagne bottle", price_cents: 4_500) }
  let!(:setup) do
    TicketingProfile.for(org).update!(enabled: true)
    ProductionTicketing.for(production).tap { |s| s.production_ticketing_products.create!(ticket_product: bottle, position: 0) }
  end
  let(:listing) { create(:ticket_listing, organization: org, show: show, slug: "rising-stars") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  let!(:order) do
    TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "1" }).tap do |o|
      o.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com", stripe_payment_intent_id: "pi_small")
    end
  end
  let!(:paid_cents) { order.total_cents }
  let(:intent) do
    Stripe::PaymentIntent.construct_from(id: "pi_small", status: "succeeded", latest_charge: "ch_small", amount: paid_cents,
                                         metadata: { type: "ticket_order", ticket_order_id: order.id.to_s })
  end

  before do
    # Two bottles added after the intent for one ticket was made.
    patch tickets_checkout_items_path(token: order.token), params: { products: { bottle.id.to_s => "2" } }, as: :json
    expect(order.reload.total_cents).to be > paid_cents
    allow(Stripe::Refund).to receive(:create)
  end

  it "won't settle on the buyer's return: the short payment is refunded and the order canceled" do
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)

    get tickets_checkout_done_path(token: order.token)

    expect(order.reload.status).to eq("canceled")
    expect(order.tickets.pluck(:status).uniq).to eq([ "void" ])
    expect(Stripe::Refund).to have_received(:create).with({ payment_intent: "pi_small" }, hash_including(:idempotency_key))
    expect(response).to redirect_to(tickets_event_path(org: org.ticketing_profile.slug, event: listing.slug))

    # Taking the bottles back off and coming back again doesn't revive it.
    get tickets_checkout_done_path(token: order.token)
    expect(order.reload.status).to eq("canceled")
  end

  it "won't settle from the webhook either" do
    event = Stripe::Event.construct_from(id: "evt_small", type: "payment_intent.succeeded", data: { object: intent })
    allow_any_instance_of(StripeWebhooksController).to receive(:webhook_secrets).and_return([ "whsec_test" ])
    allow(Stripe::Webhook).to receive(:construct_event).and_return(event)

    post "/webhooks/stripe", params: "{}", headers: { "HTTP_STRIPE_SIGNATURE" => "sig" }

    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("canceled")
    expect(OrgCashEntry.where(organization: org).count).to eq(0)
    expect(Stripe::Refund).to have_received(:create).with({ payment_intent: "pi_small" }, hash_including(:idempotency_key))
  end

  it "still settles a payment for the whole order" do
    full = Stripe::PaymentIntent.construct_from(id: "pi_small", status: "succeeded", latest_charge: "ch_full", amount: order.reload.total_cents)
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(full)

    get tickets_checkout_done_path(token: order.token)

    expect(order.reload.status).to eq("paid")
    expect(Stripe::Refund).not_to have_received(:create)
  end
end
