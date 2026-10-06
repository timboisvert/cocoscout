# frozen_string_literal: true

require "rails_helper"

# Credit passes in the browser: the pass page, paying for it (no seats, so the
# checkout is the purchase itself), the holder's page where credits become
# tickets, and the manager's editor.
RSpec.describe "Credit passes", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Twilight") }
  let!(:listing) { TicketListing.create!(show: create(:show, production: production, date_and_time: 8.days.from_now.change(hour: 19)), status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20) }
  let!(:pass) do
    org.ticket_passes.create!(name: "Twilight Punch Card", kind: "punch_card", price_cents: 6_000, credits: 5, ends_on: 40.days.from_now.to_date,
                              status: "on_sale", coverages_attributes: [ { production_id: production.id } ])
  end

  it "sells the pass, pays for it, and turns credits into tickets on the holder's page" do
    get tickets_pass_path(org: "starsandgarters", pass: pass.slug)
    expect(response.body).to include("Punch card", "5 admissions", "Twilight")

    post tickets_pass_checkout_path(org: "starsandgarters", pass: pass.slug), params: { quantity: 1 }
    purchase = TicketPurchase.order(:id).last
    expect(response).to redirect_to(tickets_pass_purchase_path(token: purchase.token))
    follow_redirect!
    expect(response.body).to include("1 × Twilight Punch Card", "Pay #{ActiveSupport::NumberHelper.number_to_currency(purchase.total_cents / 100.0)}")

    intent = Stripe::PaymentIntent.construct_from(id: "pi_cp", client_secret: "pi_cp_secret", amount: purchase.total_cents, status: "succeeded",
                                                  latest_charge: { id: "ch_cp", balance_transaction: { fee: 200 } })
    allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)
    travel 5.seconds do
      post tickets_pass_purchase_pay_path(token: purchase.token), params: { buyer_name: "Bella Swan", buyer_email: "bella@example.com" }, as: :json
    end
    expect(response.parsed_body).to eq("client_secret" => "pi_cp_secret")

    get tickets_pass_purchase_done_path(token: purchase.token)
    holding = purchase.ticket_pass_holdings.first.reload
    expect(response).to redirect_to(tickets_pass_holding_path(token: holding.token))
    expect(holding.status).to eq("active")

    follow_redirect!
    expect(response.body).to include("5 credits", listing.display_title)

    post tickets_pass_holding_use_path(token: holding.token), params: { listing_id: listing.id, people: 2 }
    order = TicketOrder.order(:id).last
    expect(response).to redirect_to(tickets_order_path(token: order.token))
    expect(order.tickets.count).to eq(2)
  end

  it "keeps another organization's show off a holder's page" do
    holding = TicketPassCredits.start!(pass: pass, quantity: 1).ticket_pass_holdings.first
    TicketPassCredits.settle!(holding, paid_at: Time.current)
    theirs = create(:ticket_listing)

    post tickets_pass_holding_use_path(token: holding.token), params: { listing_id: theirs.id }
    expect(response).to have_http_status(:not_found)
  end

  describe "managing them" do
    before do
      create(:organization_role, :manager, user: superadmin, organization: org)
      post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
      get manage_path
    end

    it "builds a season pass covering a production, and lists who has one" do
      post manage_ticket_passes_path, params: { ticket_pass: {
        name: "Twilight Season", kind: "season", price: "80", credits: "4", ends_on: 60.days.from_now.to_date.iso8601, status: "on_sale",
        coverages_attributes: { "0" => { production_id: production.id, tier_name: "General" } }
      } }
      season = org.ticket_passes.find_by(name: "Twilight Season")
      expect(response).to redirect_to(manage_ticket_pass_path(season))
      expect(season.coverages.pluck(:production_id)).to eq([ production.id ])

      get manage_ticket_pass_path(season)
      expect(response.body).to include("Who has it", "Season passes", "$20.00 a credit")
      get manage_ticket_passes_path
      expect(response.body).to include("Season pass, 4 credits")
    end
  end
end
