# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Contracts amend ticketing & tech", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let(:contract) do
    create(:contract, :active, organization: org, draft_data: {
      "ticketing" => { "tiers" => [ { "name" => "General", "price" => 25.0 } ] },
      "tech" => { "provider" => "us", "hourly_rate" => 25.0, "hours" => 2.0, "payment_method" => "cash" }
    })
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the amend step prefilled with the contract's current values" do
    get amend_ticketing_tech_manage_contract_path(contract)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("General")
  end

  it "stages ticketing & tech edits in amend_data without touching the live contract" do
    post save_amend_ticketing_tech_manage_contract_path(contract), params: {
      ticketing: { tiers: [ { name: "VIP", price: 50 } ], discount: {} }.to_json,
      tech_provider: "them"
    }
    expect(response).to redirect_to(amend_review_manage_contract_path(contract))

    # Live contract is unchanged until amendments are applied.
    expect(contract.reload.draft_tech["provider"]).to eq("us")
    expect(contract.draft_ticketing["tiers"].first["name"]).to eq("General")

    # Edits are staged in amend_data.
    expect(contract.amend_data["tech"]).to eq({ "provider" => "them" })
    expect(contract.amend_data["ticketing"]["tiers"].first["name"]).to eq("VIP")
  end

  it "applies staged ticketing & tech changes to the live contract" do
    contract.update_amend_data(
      "ticketing" => { "tiers" => [ { "name" => "VIP", "price" => 50.0 } ], "discount" => {} },
      "tech" => { "provider" => "them" }
    )

    post apply_amendments_manage_contract_path(contract)

    contract.reload
    expect(contract.draft_tech).to eq({ "provider" => "them" })
    expect(contract.draft_ticketing["tiers"].first["name"]).to eq("VIP")
    # amend staging is cleared after applying.
    expect(contract.amend_data).to eq({})
  end

  it "changing only tech to 'they provide their own' persists on apply" do
    post save_amend_ticketing_tech_manage_contract_path(contract), params: {
      ticketing: { tiers: [ { name: "General", price: 25 } ], discount: {} }.to_json,
      tech_provider: "them"
    }
    post apply_amendments_manage_contract_path(contract)

    expect(contract.reload.draft_tech["provider"]).to eq("them")
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
