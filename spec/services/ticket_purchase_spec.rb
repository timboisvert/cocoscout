# frozen_string_literal: true

require "rails_helper"

# One checkout, one payment, one order per show (Round 7's foundation for
# passes and deals): card processing is charged once and shared back onto the
# shows' orders, which always add up to the charge, and paying settles every
# show's order (its balance, books and financials) or, if a late payment finds
# a show's seats gone, refunds the whole purchase.
RSpec.describe TicketPurchase do
  let(:org) { create(:organization, :pro) }
  let(:first_show) { create(:ticket_listing, organization: org) }
  let(:second_show) { create(:ticket_listing, organization: org) }
  let!(:general) { first_show.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10) }
  let!(:late_show) { second_show.ticket_tiers.create!(name: "General", price_cents: 1_500, quantity: 10) }

  # Two shows in one checkout: the second show's order joins the first's purchase.
  def two_show_purchase
    first = TicketCheckout.start!(listing: first_show, quantities: { general.id.to_s => "2" })
    second = TicketCheckout.start!(listing: second_show, quantities: { late_show.id.to_s => "1" })
    stray = second.ticket_purchase
    second.update!(ticket_purchase: first.ticket_purchase)
    stray.destroy!
    first.ticket_purchase.price!
  end

  it "shares cents in proportion, so the parts always add up" do
    expect(TicketPricing.share(100, [ 1, 1, 1 ])).to eq([ 34, 33, 33 ])
    expect(TicketPricing.share(7, [ 4_000, 1_500 ])).to eq([ 5, 2 ])
    expect(TicketPricing.share(5, [ 0, 0 ])).to eq([ 5, 0 ])
  end

  it "prices a one-show checkout exactly as an order on its own" do
    order = TicketCheckout.start!(listing: first_show, quantities: { general.id.to_s => "2" })

    expect([ order.total_cents, order.org_net_cents ]).to eq([ 4_253, 4_000 ])
    expect(order.ticket_purchase.attributes.values_at("total_cents", "org_net_cents", "platform_fee_cents"))
      .to eq([ 4_253, 4_000, 100 ])
  end

  it "charges processing once for every show, and each show's order nets exactly its tickets" do
    purchase = two_show_purchase
    first, second = purchase.ticket_orders.to_a
    quote = TicketPricing.quote(items: [ 2_000, 2_000, 1_500 ].map { |cents| { price_cents: cents, discount_cents: 0, tax_cents: 0 } },
                                fee_mode: "buyer")

    expect(purchase.total_cents).to eq(quote.total_cents)
    expect(first.total_cents + second.total_cents).to eq(purchase.total_cents)
    expect([ first.org_net_cents, second.org_net_cents ]).to eq([ 4_000, 1_500 ])
    expect([ first.platform_fee_cents, second.platform_fee_cents ]).to eq([ 100, 50 ])
    expect(first.processing_cents + second.processing_cents).to eq(TicketPricing.processing_cents(purchase.total_cents))
  end

  it "settles every show's order on one payment, the first recording the payment" do
    purchase = two_show_purchase

    TicketPurchaseSettlement.settle!(purchase, payment_intent_id: "pi_two", charge_id: "ch_two")

    first, second = purchase.ticket_orders.reload.to_a
    expect(purchase.reload.status).to eq("paid")
    expect([ first.status, second.status ]).to eq(%w[paid paid])
    expect([ first.stripe_payment_intent_id, second.stripe_payment_intent_id ]).to eq([ "pi_two", nil ])
    expect(second.payment_intent_id).to eq("pi_two")
    expect(OrgCashEntry.where(source: [ first, second ]).pluck(:amount_cents)).to contain_exactly(4_000, 1_500)
    expect(TicketPurchaseSettlement.settle!(purchase, payment_intent_id: "pi_two")).to eq(purchase)
    expect(OrgCashEntry.where(entry_type: "ticket_sale").count).to eq(2)
  end

  it "refunds the whole purchase when a late payment finds one show's seats gone" do
    purchase = two_show_purchase
    purchase.update!(expires_at: 1.minute.ago)
    purchase.ticket_orders.update_all(expires_at: 1.minute.ago)
    late_show.update!(quantity: 1)
    TicketCheckout.start!(listing: second_show, quantities: { late_show.id.to_s => "1" })
    allow(Stripe::Refund).to receive(:create)

    TicketPurchaseSettlement.settle!(purchase, payment_intent_id: "pi_late")

    expect(Stripe::Refund).to have_received(:create).with({ payment_intent: "pi_late" }, hash_including(:idempotency_key))
    expect(purchase.reload.status).to eq("canceled")
    expect(purchase.ticket_orders.pluck(:status).uniq).to eq([ "canceled" ])
    expect(OrgCashEntry.where(entry_type: "ticket_sale")).to be_empty
  end

  it "matches the one Stripe charge to the whole purchase" do
    purchase = two_show_purchase
    TicketPurchaseSettlement.settle!(purchase, payment_intent_id: "pi_match", charge_id: "ch_match")

    category, record, expected = StripeTransactionMatcher.send(:charge, { "payment_intent" => "pi_match" })
    expect([ category, record, expected ]).to eq([ "ticket_order", purchase.primary_order, purchase.total_cents ])
  end

  it "settles from the webhook" do
    purchase = two_show_purchase
    purchase.update!(stripe_payment_intent_id: "pi_hook")
    intent = Stripe::PaymentIntent.construct_from(id: "pi_hook", latest_charge: "ch_hook",
                                                  metadata: { type: "ticket_purchase", ticket_purchase_id: purchase.id.to_s })

    StripeWebhooksController.new.send(:handle_ticket_purchase_payment, intent, "payment_intent.succeeded")

    expect(purchase.reload.ticket_orders.pluck(:status).uniq).to eq([ "paid" ])
  end
end
