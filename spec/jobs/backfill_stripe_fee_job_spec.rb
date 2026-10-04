# frozen_string_literal: true

require "rails_helper"

# Stripe's real fee lands a little after a sale; the hourly backfill fetches
# it for ticket orders paid through CocoScout (superadmin Finances reads it).
RSpec.describe BackfillStripeFeeJob do
  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  it "fills in a paid ticket order's Stripe fee, and leaves cash and comps alone" do
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "1" })
    order.update!(buyer_name: "Avery", buyer_email: "avery@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
    cash = TicketDoor.new(listing, create(:user)).sell({ general.id.to_s => "1" }, kind: "cash")

    allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_1").and_return(double(latest_charge: "ch_1"))
    allow(Stripe::Charge).to receive(:retrieve).with("ch_1").and_return(double(balance_transaction: "txn_1"))
    allow(Stripe::BalanceTransaction).to receive(:retrieve).with("txn_1").and_return(double(fee: 92))

    described_class.perform_now
    expect(order.reload.stripe_fee_cents).to eq(92)
    expect(cash.reload.stripe_fee_cents).to be_nil

    finances = TicketingFinances.new
    expect([ finances.totals.stripe_fee_cents, finances.totals.missing_fee_count, finances.totals.fees_earned_cents ]).to eq([ 92, 0, 50 ])
    expect(finances.totals.processing_margin_cents).to eq(order.processing_cents - 92)
  end
end
