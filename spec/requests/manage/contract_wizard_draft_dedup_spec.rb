# frozen_string_literal: true

require "rails_helper"

# The wizard used to mint a draft contract on GET /contracts/wizard/new?contractor_id=.
# Turbo prefetches links on hover, so every hover over "New Contract" on a
# contractor's page created another identical step-2 draft (five in 30 seconds in
# prod). A GET must never create; creation happens only on POST create_draft, and
# even that reuses an untouched draft instead of stacking clones.
RSpec.describe "Manage::ContractWizard draft dedup", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:contractor) { create(:contractor, organization: org, name: "Windy City Witches") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "GET new with contractor_id (the hover-prefetch target)" do
    it "never creates a contract" do
      expect {
        5.times { get manage_new_contract_wizard_path(contractor_id: contractor.id) }
      }.not_to change(Contract, :count)
    end

    it "renders the picker with the contractor preselected when there is no draft to reuse" do
      get manage_new_contract_wizard_path(contractor_id: contractor.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(<option value="#{contractor.id}" selected>))
    end

    it "redirects into an existing untouched draft instead" do
      post manage_create_draft_contract_wizard_path, params: { contract: { contractor_id: contractor.id } }
      draft = Contract.last

      expect {
        get manage_new_contract_wizard_path(contractor_id: contractor.id)
      }.not_to change(Contract, :count)
      expect(response).to redirect_to(manage_production_contract_wizard_path(draft))
    end
  end

  describe "POST create_draft" do
    it "creates one draft and reuses it on repeated submits" do
      expect {
        3.times { post manage_create_draft_contract_wizard_path, params: { contract: { contractor_id: contractor.id } } }
      }.to change(Contract, :count).by(1)

      draft = Contract.last
      expect(response).to redirect_to(manage_production_contract_wizard_path(draft))
      expect(draft.contractor_name).to eq("Windy City Witches")
      expect(draft.wizard_step).to eq(2)
    end

    it "accepts a top-level contractor_id, the way the contractor page's POST link sends it" do
      expect {
        post manage_create_draft_contract_wizard_path(contractor_id: contractor.id)
      }.to change(Contract, :count).by(1)
      expect(Contract.last.contractor_id).to eq(contractor.id)
    end

    it "starts a fresh draft once the earlier one has actually been worked on" do
      post manage_create_draft_contract_wizard_path, params: { contract: { contractor_id: contractor.id } }
      Contract.last.update!(production_name: "Witches Cabaret")

      expect {
        post manage_create_draft_contract_wizard_path, params: { contract: { contractor_id: contractor.id } }
      }.to change(Contract, :count).by(1)
    end
  end
end
