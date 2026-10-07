# frozen_string_literal: true

require "rails_helper"

# A contracted production's name and description change through its contract
# (Amend → Change the basic info), with nothing to re-sign (Tim, 2026-10-07).
# While the contract runs, the production's own settings page shows them and
# points there.
RSpec.describe "Contracts — change the basic info", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party", name: "Nuns4Fun", description: "Old words") }
  let!(:contract) { create(:contract, :active, organization: org, production: production, contractor_name: "Habit Theater", production_name: "Nuns4Fun") }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  before { sign_in(owner) }

  it "is the first choice when amending" do
    get amend_choose_manage_contract_path(contract)

    body = response.body
    expect(body).to include("Change the basic info", amend_basics_manage_contract_path(contract))
    expect(body.index("Change the basic info")).to be < body.index("Change the dates")
  end

  it "opens with the production's name and description" do
    get amend_basics_manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('value="Nuns4Fun"', "Old words")
  end

  it "renames the production and the contract and rewrites the description, with no new version" do
    versions_before = contract.contract_versions.count

    post apply_amend_basics_manage_contract_path(contract),
         params: { production_name: "Nuns4Fun: The Sequel", description: "Two nuns, one stage." }

    expect(response).to redirect_to(manage_contract_path(contract))
    expect(flash[:notice]).to eq("Renamed to Nuns4Fun: The Sequel, with its new description.")
    expect(production.reload.name).to eq("Nuns4Fun: The Sequel")
    expect(production.description).to eq("Two nuns, one stage.")
    expect(contract.reload.production_name).to eq("Nuns4Fun: The Sequel")
    expect(contract.contract_versions.count).to eq(versions_before)
  end

  it "brings along the production's other contracts that still carry its old name" do
    other = create(:contract, :completed, organization: org, production: production, production_name: "Nuns4Fun")
    renamed_before = create(:contract, :completed, organization: org, production: production, production_name: "Something Else")

    post apply_amend_basics_manage_contract_path(contract), params: { production_name: "Nun Better", description: "Old words" }

    expect(flash[:notice]).to eq("Renamed to Nun Better.")
    expect(other.reload.production_name).to eq("Nun Better")
    expect(renamed_before.reload.production_name).to eq("Something Else")
  end

  it "clears the description when it's emptied" do
    post apply_amend_basics_manage_contract_path(contract), params: { production_name: "Nuns4Fun", description: "  " }

    expect(flash[:notice]).to eq("Updated the description.")
    expect(production.reload.description).to be_nil
  end

  it "refuses a blank name and changes nothing" do
    post apply_amend_basics_manage_contract_path(contract), params: { production_name: " ", description: "New words" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Give the production a name.")
    expect(production.reload.name).to eq("Nuns4Fun")
    expect(production.description).to eq("Old words")
  end

  it "says so when nothing changed" do
    post apply_amend_basics_manage_contract_path(contract), params: { production_name: "Nuns4Fun", description: "Old words" }

    expect(flash[:notice]).to eq("Nothing to change.")
  end

  it "never reaches another organization's contract" do
    other_org = create(:organization, :pro)
    other_production = create(:production, organization: other_org, production_type: "third_party", name: "Theirs")
    theirs = create(:contract, :active, organization: other_org, production: other_production)

    post apply_amend_basics_manage_contract_path(theirs), params: { production_name: "Mine now", description: "" }

    expect(response).to have_http_status(:not_found)
    expect(other_production.reload.name).to eq("Theirs")
  end

  describe "the production's settings page" do
    it "shows the name and description and points to the contract while it runs" do
      get edit_manage_production_path(production)

      body = response.body
      expect(body).to include("Nuns4Fun", "Old words", "Change in the contract", amend_basics_manage_contract_path(contract))
      expect(body).to include("These change through the contract with Habit Theater")
      expect(body).not_to include('name="production[name]"', 'name="production[description]"', "Save Changes")
    end

    it "edits them in place once the contract is finished" do
      contract.update!(status: :completed, completed_at: Time.current)

      get edit_manage_production_path(production)

      expect(response.body).to include('name="production[name]"', 'name="production[description]"', "Save Changes")
      expect(response.body).not_to include("Change in the contract")
    end

    it "edits them in place for an in-house production" do
      in_house = create(:production, organization: org, name: "Boylesque")

      get edit_manage_production_path(in_house)

      expect(response.body).to include('name="production[description]"')
    end

    it "sends the production page's 'Add one' to the contract" do
      production.update!(description: nil)

      get manage_production_path(production)

      expect(response.body).to include("No description yet.", amend_basics_manage_contract_path(contract))
    end

    it "gives a producer on the team the words but no way into the contract" do
      producer = create(:user, password: password)
      create(:organization_role, user: producer, organization: org, company_role: "member")
      ProductionPermission.create!(user: producer, production: production, role: "manager")
      get signout_path
      sign_in(producer)

      get edit_manage_production_path(production)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Old words", "which your organization's managers look after")
      expect(response.body).not_to include(amend_basics_manage_contract_path(contract), manage_contract_path(contract))
    end
  end
end
