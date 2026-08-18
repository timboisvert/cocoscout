# frozen_string_literal: true

require "rails_helper"

# The contract page's "Contract Terms" panel: the deal as written — direction,
# pricing, ticketing, services — so nobody has to open the PDF.
RSpec.describe "Manage::Contracts show — Contract Terms", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def make_contract(draft_data)
    create(:contract, :active, organization: org, production: production, draft_data: draft_data)
  end

  it "shows a revenue share where we sell, with the ticket tiers and discount" do
    contract = make_contract(
      "payment_structure" => "revenue_share",
      "payment_config" => {
        "settlement_basis" => "revenue_share", "who_sells_tickets" => "org",
        "revenue_source" => "ticket_sales", "revenue_our_share" => "50", "revenue_their_share" => "50",
        "revenue_settlement" => "same_day", "accepted_payment_methods" => [ "online" ]
      },
      "ticketing" => {
        "tiers" => [ { "name" => "General Admission", "price" => 20 }, { "name" => "VIP", "price" => 35 } ],
        "discounts" => [ { "code" => "FRIENDS", "amount" => 5, "amount_type" => "fixed", "applies_to" => "all" } ]
      }
    )

    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("Contract Terms")
    # We sell → we pay them their share: money goes out.
    expect(body).to include("We pay them")
    expect(body).to include("Revenue share on ticket sales — we keep 50%, they keep 50%")
    expect(body).to include("Who sells the tickets")
    expect(body).to include("Settled same day")
    expect(body).to include("General Admission")
    expect(body).to include("$35.00")
    expect(body).to include("FRIENDS")
    # The old standalone boxes are gone.
    expect(body).not_to include(">Ticketing</h3>")
    expect(body).not_to include("Revenue Projection")
  end

  it "shows a flat rental they pay us, with no ticketing section" do
    contract = make_contract(
      "payment_structure" => "flat_fee",
      "payment_config" => {
        "settlement_basis" => "flat", "flat_fee_direction" => "incoming", "flat_fee_amount" => "350",
        "flat_fee_has_deposit" => true, "flat_fee_deposit_amount" => "100",
        "accepted_payment_methods" => [ "online", "zelle" ]
      }
    )

    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("They pay us")
    expect(body).to include("Flat fee of $350.00 — they pay us")
    expect(body).to include("$100.00 upfront")
    expect(body).to include("No tickets on this deal")
    expect(body).not_to include("uppercase tracking-wide mb-2\">Ticketing")
  end

  it "shows a contractor-sells split with a service on top" do
    contract = make_contract(
      "payment_structure" => "revenue_share",
      "payment_config" => {
        "settlement_basis" => "revenue_share", "who_sells_tickets" => "contractor",
        "revenue_our_share" => "40", "revenue_their_share" => "60", "revenue_settlement" => "weekly"
      },
      "services" => [
        { "name" => "Booth Tech", "unit" => "hourly", "quantity" => 2.0, "unit_price" => 25.0, "direction" => "incoming" }
      ]
    )

    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("They pay us")
    expect(body).to include("They do — they report their sales")
    expect(body).to include("Booth Tech")
    expect(body).to include("2 hr × $25.00")
    expect(body).to include("+$50.00")
  end

  it "shows a per-event service settled out of their payout" do
    contract = make_contract(
      "payment_structure" => "flat_fee",
      "payment_config" => { "settlement_basis" => "revenue_minus_fee", "flat_fee_direction" => "ticket_revenue_minus_fee",
                            "flat_fee_amount" => "200", "flat_fee_basis" => "per_show", "who_sells_tickets" => "org" },
      "services" => [
        { "name" => "Box Office", "unit" => "hourly", "quantity" => 4.0, "unit_price" => 30.0, "direction" => "incoming",
          "settlement" => "payout_deduction", "per_event" => true,
          "events" => [ { "starts_at" => "2026-09-01T19:00", "hours" => 2 }, { "starts_at" => "2026-09-08T19:00", "hours" => 2 } ] }
      ]
    )

    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("They keep the ticket revenue, less our $200.00 per show fee")
    expect(body).to include("2 events · 4 hrs × $30.00/hr")
    expect(body).to include("taken out of their payout")
    # We sell but set no tiers yet — the panel says so instead of hiding it.
    expect(body).to include("no ticket tiers are set yet")
  end
end
