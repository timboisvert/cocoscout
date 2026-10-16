# frozen_string_literal: true

require "rails_helper"

# A finished contract archives its production; the next contract for the same
# show should still be able to pick it (labeled archived) and bring it back.
RSpec.describe "Manage::ContractWizard archived productions", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:live) { create(:production, organization: org, name: "Live Show") }
  let!(:shelved) { create(:production, organization: org, name: "Shelved Show", archived_at: 1.month.ago) }
  let!(:contract) { create(:contract, organization: org, status: :draft, wizard_step: 2) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "lists archived productions after the active ones, labeled" do
    get manage_production_contract_wizard_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Live Show")
    expect(response.body).to include("Shelved Show (archived)")
    expect(response.body.index("Live Show")).to be < response.body.index("Shelved Show (archived)")
  end

  it "accepts an archived production as the link" do
    post manage_production_contract_wizard_path(contract),
         params: { production_mode: "existing", link_production_id: shelved.id }

    expect(contract.reload.draft_data["link_production_id"]).to eq(shelved.id)
    expect(contract.production_name).to eq("Shelved Show")
  end
end
