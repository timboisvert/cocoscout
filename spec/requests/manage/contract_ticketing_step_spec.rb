# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract wizard ticketing step", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:contract) { create(:contract, organization: org, contractor_name: "Rental Co", status: "draft") }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    # Only reachable when we sell the tickets.
    contract.update_draft_step(:payment_config, { "who_sells_tickets" => "org" })
  end

  it "presents tiers and discounts as add-through-a-modal lists" do
    get manage_ticketing_contract_wizard_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add a ticket tier")
    expect(response.body).to include("Add a discount code")
    expect(response.body).to include(%(data-contract-ticketing-target="tierModal"))
    expect(response.body).to include(%(data-contract-ticketing-target="discountModal"))
  end

  it "saves multiple tiers and discount codes" do
    payload = {
      tiers: [ { name: "General", price: 20 }, { name: "VIP", price: 50 } ],
      discounts: [
        { code: "FRIENDS", amount: 10, amount_type: "percent", applies_to: "all", tier_names: [] },
        { code: "VIPONLY", amount: 5, amount_type: "fixed", applies_to: "specific", tier_names: [ "VIP" ] }
      ]
    }

    post manage_ticketing_contract_wizard_path(contract), params: { ticketing: payload.to_json }

    ticketing = contract.reload.draft_ticketing
    expect(ticketing["tiers"].size).to eq(2)
    expect(Contract.ticketing_discounts(ticketing).map { |d| d["code"] }).to contain_exactly("FRIENDS", "VIPONLY")
  end

  it "normalizes a legacy single discount into the list" do
    contract.update_draft_step(:ticketing, {
      "tiers" => [ { "name" => "GA", "price" => 15 } ],
      "discount" => { "code" => "OLD", "amount" => 5, "amount_type" => "fixed", "applies_to" => "all" }
    })

    expect(Contract.ticketing_discounts(contract.draft_ticketing).map { |d| d["code"] }).to eq([ "OLD" ])
  end
end
