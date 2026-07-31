# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract wizard send gate (require a CocoScout user)", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:contract) { create(:contract, organization: org, contractor_name: "Sound Co", contractor_email: "sound@example.com") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "resolves signer_person_record from a linked person or matching email" do
    expect(contract.signer_person_record).to be_nil
    person = create(:person, name: "Dan", email: "sound@example.com")
    org.people << person
    expect(contract.reload.signer_person_record).to eq(person) # email match
  end

  it "blocks sending when no CocoScout user is attached" do
    post manage_send_contract_wizard_path(contract)

    expect(response).to redirect_to(manage_send_contract_wizard_path(contract))
    expect(flash[:alert]).to match(/Attach a CocoScout user/)
    expect(contract.reload.signing_state).not_to eq("out_for_signature")
  end

  it "link_signer attaches an existing person and creates the contractor" do
    person = create(:person, name: "Dan", email: "dan@example.com")

    post manage_link_signer_contract_wizard_path(contract), params: { person_id: person.id }

    contract.reload
    expect(contract.contractor).to be_present
    expect(contract.contractor.person).to eq(person)
    expect(contract.signer_person_record).to eq(person)
  end
end
