# frozen_string_literal: true

require "rails_helper"

# Cancel in the wizard while re-signing an amendment (Tim, 2026-10-18): it
# said "draft discarded", deleted nothing (the contract isn't a draft), and
# left the contract reading "Continue setup". Now the amendment is thrown
# away and the contract stays as it was signed.
RSpec.describe "Discarding a staged amendment", type: :request do
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
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
    contract.send_for_signature!
    contract.execute_by_signature!(signer_name: "Quinn", signer_email: "q@example.com",
                                   request: double(remote_ip: "1.2.3.4", user_agent: "rspec"))
    contract.reload
    contract.update_amend_data(
      "payment_config" => { "revenue_our_share" => "60", "revenue_their_share" => "40" },
      "new_bookings" => [ { "location_id" => location.id, "starts_at" => 3.weeks.from_now.change(hour: 20).iso8601, "duration" => "2" } ]
    )
    post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }
    contract.reload
  end

  it "offers to discard the amendment, not a draft, from the wizard" do
    get manage_sign_contract_wizard_path(contract)
    expect(response.body).to include("Discard this amendment?", "Discard amendment")
    expect(response.body).not_to include("Discard this draft?")
  end

  it "throws the amendment away and leaves the contract as it was signed" do
    expect(contract.amendment_pending?).to be(true)
    expect(contract.signing_state).to eq("unsent")
    version_count = contract.contract_versions.count

    delete manage_cancel_contract_wizard_path(contract)
    expect(response).to redirect_to(manage_contract_path(contract))
    expect(flash[:notice]).to eq("Amendment discarded. The contract stays as it was signed.")

    contract.reload
    expect(Contract.exists?(contract.id)).to be(true)
    expect(contract.status).to eq("active")
    expect(contract.amendment_pending?).to be(false)
    expect(contract.amend_data).to eq({})
    expect(contract.contract_versions.count).to eq(version_count - 1)
    expect(contract.signing_state).to eq("executed")

    get manage_contract_path(contract)
    expect(response.body).not_to include("Continue setup", "hasn&#39;t been prepared and signed yet")
  end

  it "still deletes a draft contract" do
    draft = create(:contract, organization: org, contractor_name: "Draft Person", status: "draft")
    delete manage_cancel_contract_wizard_path(draft)
    expect(response).to redirect_to(manage_contracts_path)
    expect(Contract.exists?(draft.id)).to be(false)
  end
end

# Signed but not sent, and something needs a tweak (Tim, 2026-10-18): the
# signature comes off, the changes stay, and signing happens again after.
RSpec.describe "Unsigning before sending", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:template) { org.contract_templates.create!(name: "Standard", content: "<p>For {{contractor_name}} — {{production_name}}</p>") }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "reopens a staged amendment with its changes kept, and the contract reads as signed meanwhile" do
    contract = create(:contract, :active, organization: org, production: production, contractor_name: "Quinn James",
                                          signing_mode: :esign, contract_template: template)
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
    contract.send_for_signature!
    contract.execute_by_signature!(signer_name: "Quinn", signer_email: "q@example.com", request: double(remote_ip: "1.2.3.4", user_agent: "rspec"))
    contract.reload
    changes = { "payment_config" => { "revenue_our_share" => "60", "revenue_their_share" => "40" },
                "new_bookings" => [ { "location_id" => location.id, "starts_at" => 3.weeks.from_now.change(hour: 20).iso8601, "duration" => "2" } ] }
    contract.update_amend_data(changes)
    post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }
    post manage_sign_contract_wizard_path(contract), params: { signer_name: "Tim", agree: "1" }
    expect(contract.reload.signing_state).to eq("awaiting_send")

    get manage_send_contract_wizard_path(contract)
    expect(response.body).to include("Unsign and change something", manage_unsign_contract_wizard_path(contract))

    post manage_unsign_contract_wizard_path(contract)
    expect(response).to redirect_to(amend_review_manage_contract_path(contract))
    contract.reload
    expect(contract.amendment_pending?).to be(false)
    expect(contract.signing_state).to eq("executed")
    expect(contract.amend_data).to include(changes)

    # Staged and signed again, as if for the first time.
    post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }
    expect(contract.reload.amendment_pending?).to be(true)
    post manage_sign_contract_wizard_path(contract), params: { signer_name: "Tim", agree: "1" }
    expect(contract.reload.signing_state).to eq("awaiting_send")
  end

  it "takes the signature off a first contract and goes back to Review" do
    contract = create(:contract, organization: org, production: production, contractor_name: "Quinn James", status: "draft",
                                 signing_mode: :esign, contract_template: template)
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
    expect(contract.reload.signing_state).to eq("awaiting_send")

    post manage_unsign_contract_wizard_path(contract)
    expect(response).to redirect_to(manage_review_contract_wizard_path(contract))
    contract.reload
    expect(contract.signing_state).to eq("unsent")
    expect(contract.organization_signature).to be_nil
    expect(contract.contract_versions.count).to eq(1)
  end
end
