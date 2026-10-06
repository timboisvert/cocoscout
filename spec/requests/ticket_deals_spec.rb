# frozen_string_literal: true

require "rails_helper"

# Deals on another show (Tim, 2026-10-05): "You're buying Boylesque; add
# tonight's Laugh Along Live for $5 off", at checkout and for a few days
# after. One deal per ticket bought; returning the tickets takes it back.
RSpec.describe "Ticket deals", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:boylesque) { create(:production, organization: org, name: "Boylesque") }
  let(:laugh_along) { create(:production, organization: org, name: "Laugh Along Live") }
  let(:night) { 6.days.from_now.change(hour: 19) }
  let(:early) { TicketListing.create!(show: create(:show, production: boylesque, date_and_time: night), status: "on_sale") }
  let(:late) { TicketListing.create!(show: create(:show, production: laugh_along, date_and_time: night.change(hour: 21, min: 30)), status: "on_sale") }
  let!(:early_general) { early.ticket_tiers.create!(name: "General", price_cents: 2_500, quantity: 50) }
  let!(:late_general) { late.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50) }
  let!(:offer) do
    org.ticket_offers.create!(name: "Boylesque → Laugh Along", trigger_scope: "production", trigger_production: boylesque,
                              target_scope: "same_night", target_production: laugh_along, deal_kind: "amount_off", amount_cents: 500)
  end

  before { allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_deal")) }

  def start(count)
    TicketCheckout.start!(listing: early, quantities: { early_general.id.to_s => count.to_s })
  end

  it "offers the same night's other show at checkout, and adds up to one per ticket on the same hold" do
    order = start(2)
    get tickets_checkout_path(token: order.token)
    expect(response.body).to include("Make it a night", "Laugh Along Live")
    expect(offer.reload.shown_count).to eq(1)

    patch tickets_checkout_items_path(token: order.token), params: { products: {}, deals: { offer.id => 5 } }, as: :json
    expect(response).to have_http_status(:ok)
    purchase = order.reload.ticket_purchase
    deal_order = purchase.ticket_orders.find_by(ticket_listing: late)
    expect(deal_order.tickets.pluck(:price_cents, :discount_cents, :ticket_offer_id)).to eq([ [ 2_000, 500, offer.id ] ] * 2)
    expect(response.parsed_body["summary_html"]).to include("2 × General · ")
    expect(response.parsed_body["total_cents"]).to eq(purchase.reload.total_cents)

    patch tickets_checkout_items_path(token: order.token), params: { products: {}, deals: { offer.id => 0 } }, as: :json
    expect(purchase.ticket_orders.reload.size).to eq(1)
    expect(late.inventory.remaining(tier: late_general)).to eq(50)
  end

  it "takes the deal back when the tickets that earned it are returned" do
    order = start(1)
    TicketCheckout.set_deals!(order, { offer.id.to_s => "1" })
    TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_deal")
    deal_ticket = order.ticket_purchase.ticket_orders.find_by(ticket_listing: late).tickets.first

    refund = TicketOrderRefund.issue!(order.reload)
    expect(refund.repriced_cents).to eq(500)
    expect(deal_ticket.reload.discount_cents).to eq(0)
    expect(BooksReconciliation.check(org)).to eq([])
  end

  it "offers it again after paying, and opens a checkout remembering the purchase that earned it" do
    order = start(2)
    TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_first")
    order.reload.update!(buyer_name: "Ann Example", buyer_email: "ann@example.com")

    get tickets_order_path(token: order.token)
    expect(response.body).to include("Make it a night", "Add to my night")

    post tickets_order_add_deal_path(token: order.token, offer: offer.id), params: { quantity: 3 }
    expect(flash[:alert]).to eq("You can add up to 2 with your tickets.")

    post tickets_order_add_deal_path(token: order.token, offer: offer.id), params: { quantity: 2 }
    new_order = TicketOrder.order(:id).last
    expect(response).to redirect_to(tickets_checkout_path(token: new_order.token))
    expect(new_order.ticket_purchase.earned_by_purchase).to eq(order.ticket_purchase)
    expect(new_order.buyer_email).to eq("ann@example.com")
    expect(TicketCheckout.deal_room(order, offer)).to eq(0)

    travel 3.days do
      expect(TicketCheckout.deals_after(order.reload)).to eq([])
    end
  end

  it "says nothing on a night the other production isn't on, or when it's off" do
    late.show.update!(date_and_time: night + 1.day)
    expect(TicketCheckout.deals_for(start(1))).to eq([])
    late.show.update!(date_and_time: night.change(hour: 21))
    offer.update!(active: false)
    expect(TicketCheckout.deals_for(start(1))).to eq([])
  end

  describe "managing deals" do
    before do
      create(:organization_role, :manager, user: superadmin, organization: org)
      post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
      get manage_path
    end

    it "lists deals with how often they were shown and taken, and builds a new one" do
      get manage_ticket_offers_path
      expect(response.body).to include("Boylesque → Laugh Along", "$5.00 off")

      get manage_new_ticket_offer_path
      expect(response).to have_http_status(:ok)
      post manage_ticket_offers_path, params: { ticket_offer: {
        name: "Twenty off", trigger_scope: "any", target_scope: "listing", target_tier_id: late_general.id,
        deal_kind: "percent_off", percent: "20", active: "1", after_purchase_days: "2"
      } }
      expect(response).to redirect_to(manage_ticket_offers_path)
      expect(org.ticket_offers.find_by(name: "Twenty off").deal_price_cents(late_general)).to eq(1_600)

      get manage_edit_ticket_offer_path(org.ticket_offers.find_by(name: "Twenty off"))
      expect(response).to have_http_status(:ok)
    end

    it "never offers another organization's show" do
      theirs = create(:ticket_listing).ticket_tiers.create!(name: "General", price_cents: 1_000, quantity: 5)
      post manage_ticket_offers_path, params: { ticket_offer: {
        name: "Sneaky", trigger_scope: "any", target_scope: "listing", target_tier_id: theirs.id, deal_kind: "amount_off", amount: "1"
      } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(org.ticket_offers.find_by(name: "Sneaky")).to be_nil
    end
  end
end
