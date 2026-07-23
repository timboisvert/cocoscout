# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract wizard review step", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, organization: org, production: production, contractor_name: "Gigi",
                      contract_start_date: Date.current, contract_end_date: Date.current + 7)
  end

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    contract.update_draft_step(:payment_structure, "revenue_share")
    contract.update_draft_step(:payment_config, {
      "who_sells_tickets" => "org", "settlement_basis" => "revenue_share",
      "revenue_our_share" => "30", "revenue_their_share" => "70", "revenue_settlement" => "same_day",
      "accepted_payment_methods" => %w[online]
    })
    contract.update_draft_step(:ticketing, {
      "tiers" => [ { "name" => "GA", "price" => 20 } ],
      "discounts" => [ { "code" => "FRIENDS", "amount" => 10, "amount_type" => "percent", "applies_to" => "all" } ]
    })
    contract.update_draft_step(:services, [
      { "name" => "Technical services", "quantity" => 3, "unit_price" => 25, "unit" => "hourly", "direction" => "incoming" }
    ])
  end

  it "shows the full deal, ticketing, services and payments without needing to go back" do
    get manage_review_contract_wizard_path(contract)

    expect(response).to have_http_status(:ok)
    # The deal terms.
    expect(response.body).to include("The deal")
    expect(response.body).to include("we keep 30%, they keep 70%")
    # Ticketing with the tier and the discount.
    expect(response.body).to include("GA")
    expect(response.body).to include("FRIENDS")
    # Services, priced.
    expect(response.body).to include("Technical services")
    expect(response.body).to include("Services (1)")
    # The old Tech section is gone.
    expect(response.body).not_to include(">Tech<")
  end
end
