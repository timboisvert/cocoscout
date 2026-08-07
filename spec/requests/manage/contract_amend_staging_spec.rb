# frozen_string_literal: true

require "rails_helper"

# An amendment that needs a signature is a proposal, not a fact. Until the
# counterparty signs, the live contract must keep describing the deal actually
# in force — otherwise the org's records, and the contractor's own My Contracts
# page, show terms nobody agreed to.
RSpec.describe "Amendments are staged until signed", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:template) { org.contract_templates.create!(name: "Standard", content: "<p>For {{contractor_name}} — {{production_name}}</p>") }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor_name: "Quinn James",
                               signing_mode: :esign, contract_template: template)
  end

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    # v1, signed, so amending is a re-signature rather than a first signature.
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
    contract.send_for_signature!
    contract.execute_by_signature!(signer_name: "Quinn", signer_email: "q@example.com",
                                   request: double(remote_ip: "1.2.3.4", user_agent: "rspec"))
    contract.reload
  end

  # A rate change plus a new date, staged the way the wizard stages them.
  def stage_changes!
    contract.update_amend_data(
      "payment_config" => { "revenue_our_share" => "60", "revenue_their_share" => "40" },
      "new_bookings" => [ { "location_id" => location.id, "starts_at" => 3.weeks.from_now.change(hour: 20).iso8601, "duration" => "2" } ]
    )
  end

  describe "when it needs a signature" do
    it "changes nothing on the live contract" do
      stage_changes!
      rentals_before = contract.space_rentals.count
      shows_before = production.shows.count
      config_before = contract.draft_payment_config

      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }

      contract.reload
      expect(contract.space_rentals.count).to eq(rentals_before)
      expect(production.shows.count).to eq(shows_before)
      expect(contract.draft_payment_config).to eq(config_before)
    end

    it "cuts a version holding the proposal, and sends you to sign it" do
      stage_changes!

      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }

      version = contract.reload.current_version
      expect(version.version_number).to eq(2)
      expect(version.staged_amendment).to be_present
      expect(version.executed_at).to be_nil
      expect(contract.signing_state).to eq("unsent")
      expect(contract.amendment_pending?).to be(true)
      expect(response).to redirect_to(manage_sign_contract_wizard_path(contract))
    end

    it "refuses to start another amendment while one is waiting" do
      stage_changes!
      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }

      stage_changes!
      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }

      expect(flash[:alert]).to include("already an amendment waiting")
      expect(contract.reload.contract_versions.count).to eq(2)
    end

    it "applies everything the moment they sign, and not before" do
      stage_changes!
      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }
      rentals_before = contract.reload.space_rentals.count

      contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
      contract.send_for_signature!
      contract.execute_by_signature!(signer_name: "Quinn", signer_email: "q@example.com",
                                     request: double(remote_ip: "1.2.3.4", user_agent: "rspec"))

      contract.reload
      expect(contract.space_rentals.count).to eq(rentals_before + 1)
      expect(contract.draft_payment_config["revenue_our_share"]).to eq("60")
      expect(contract.current_version.executed_at).to be_present
      expect(contract.amendment_pending?).to be(false)
      expect(contract.amend_data).to be_blank
    end

    it "renders the document from the proposal, not from the live contract" do
      contract.update_amend_data("production_name" => "Renamed For The Document")

      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }

      # The document describes the proposal...
      expect(contract.reload.current_version.content_snapshot).to include("Renamed For The Document")
      # ...while the contract itself still describes what's in force.
      expect(contract.production_name).not_to eq("Renamed For The Document")
    end
  end

  describe "when it's an internal correction" do
    it "takes effect immediately, no signature involved" do
      stage_changes!
      rentals_before = contract.space_rentals.count

      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "0" }

      contract.reload
      expect(contract.space_rentals.count).to eq(rentals_before + 1)
      expect(contract.current_version.executed_at).to be_present
      expect(contract.amendment_pending?).to be(false)
      expect(response).to redirect_to(manage_contract_path(contract))
    end
  end

  describe "the Change dates flow" do
    it "still applies immediately — no signature, so nothing to wait for" do
      rental = contract.space_rentals.create!(location: location, starts_at: 3.weeks.from_now.change(hour: 20),
                                              ends_at: 3.weeks.from_now.change(hour: 22), confirmed: true)

      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "remove" } } }

      expect(SpaceRental.exists?(rental.id)).to be(false)
    end
  end
end
