# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Contracts amend ticketing & tech", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let(:contract) do
    create(:contract, :active, organization: org, draft_data: {
      "ticketing" => { "tiers" => [ { "name" => "General", "price" => 25.0 } ] },
      "services" => []
    })
  end
  let!(:service_option) do
    org.contract_service_options.create!(name: "Technical services", default_price_cents: 2500, unit: "hourly", default_direction: "incoming")
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the amend step prefilled with the contract's current values" do
    get amend_ticketing_tech_manage_contract_path(contract)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("General")
  end

  it "stages ticketing & service edits in amend_data without touching the live contract" do
    post save_amend_ticketing_tech_manage_contract_path(contract), params: {
      ticketing: { tiers: [ { name: "VIP", price: 50 } ], discounts: [] }.to_json,
      services: { "0" => { include: "1", name: "Technical services", unit: "hourly", quantity: "3", unit_price: "25", direction: "incoming" } }
    }
    expect(response).to redirect_to(amend_review_manage_contract_path(contract))

    # Live contract is unchanged until amendments are applied.
    expect(contract.reload.draft_services).to eq([])
    expect(contract.draft_ticketing["tiers"].first["name"]).to eq("General")

    # Edits are staged in amend_data.
    expect(contract.amend_data["services"].first["name"]).to eq("Technical services")
    expect(contract.amend_data["ticketing"]["tiers"].first["name"]).to eq("VIP")
  end

  it "applies staged ticketing & service changes, billing the new services" do
    contract.update_amend_data(
      "ticketing" => { "tiers" => [ { "name" => "VIP", "price" => 50.0 } ], "discounts" => [] },
      "services" => [ { "name" => "Technical services", "quantity" => 3, "unit_price" => 25, "unit" => "hourly", "direction" => "incoming" } ]
    )

    expect {
      post apply_amendments_manage_contract_path(contract)
    }.to change { contract.contract_payments.where(description: "Technical services").count }.by(1)

    contract.reload
    expect(contract.draft_services.first["name"]).to eq("Technical services")
    expect(contract.contract_payments.find_by(description: "Technical services").amount).to eq(75)
    expect(contract.draft_ticketing["tiers"].first["name"]).to eq("VIP")
    # amend staging is cleared after applying.
    expect(contract.amend_data).to eq({})
  end

  it "re-billing services drops the old pending payment and bills the new one" do
    contract.update_draft_step(:services, [ { "name" => "Technical services", "quantity" => 2, "unit_price" => 25, "unit" => "hourly", "direction" => "incoming" } ])
    old = contract.contract_payments.create!(description: "Technical services", amount: 50, direction: "incoming", due_date: Date.current, status: "pending")

    contract.update_amend_data(
      "services" => [ { "name" => "Technical services", "quantity" => 4, "unit_price" => 25, "unit" => "hourly", "direction" => "incoming" } ]
    )
    post apply_amendments_manage_contract_path(contract)

    expect(ContractPayment.exists?(old.id)).to be(false)
    expect(contract.reload.contract_payments.find_by(description: "Technical services").amount).to eq(100)
  end

  it "leaves an already-paid service payment untouched when re-billing" do
    contract.update_draft_step(:services, [ { "name" => "Technical services", "quantity" => 2, "unit_price" => 25, "unit" => "hourly", "direction" => "incoming" } ])
    paid = contract.contract_payments.create!(description: "Technical services", amount: 50, direction: "incoming", due_date: Date.current, status: "paid")

    contract.update_amend_data("services" => [])
    post apply_amendments_manage_contract_path(contract)

    expect(ContractPayment.exists?(paid.id)).to be(true)
  end

  describe "production name" do
    let!(:production) { create(:production, organization: org, name: "Music & Improv Show").tap { |p| contract.update!(production: p) } }

    it "prefills the amend step with the current name" do
      contract.update!(production_name: "Music & Improv Show")
      get amend_ticketing_tech_manage_contract_path(contract)
      expect(response.body).to include("Music &amp; Improv Show")
    end

    it "renames the contract and the linked production on apply" do
      contract.update!(production_name: "Music & Improv Show")

      post save_amend_ticketing_tech_manage_contract_path(contract), params: {
        production_name: "The Midnight Riot",
        ticketing: { tiers: [], discount: {} }.to_json,
        tech_provider: "them"
      }
      post apply_amendments_manage_contract_path(contract)

      expect(contract.reload.production_name).to eq("The Midnight Riot")
      expect(production.reload.name).to eq("The Midnight Riot")
    end

    it "leaves the name untouched when the field is left blank" do
      contract.update!(production_name: "Music & Improv Show")

      post save_amend_ticketing_tech_manage_contract_path(contract), params: {
        production_name: "",
        ticketing: { tiers: [], discount: {} }.to_json,
        tech_provider: "them"
      }
      post apply_amendments_manage_contract_path(contract)

      expect(contract.reload.production_name).to eq("Music & Improv Show")
      expect(production.reload.name).to eq("Music & Improv Show")
    end
  end
end
