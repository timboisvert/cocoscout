# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract signing page", type: :request do
  let(:password) { "Password123!" }
  let(:org) { create(:organization) }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Katie Rae", email: user.email_address) }
  let(:contractor) { create(:contractor, organization: org, person: person, email: person.email) }
  let!(:contract) do
    create(:contract, :active, organization: org, contractor: contractor,
           contractor_name: "Katie Rae", contractor_email: person.email,
           signing_state: "out_for_signature", signing_token: SecureRandom.urlsafe_base64(24))
  end

  it "shows a CocoScout identity card to the signed-in member" do
    post handle_signin_path, params: { email_address: user.email_address, password: password }

    get sign_contract_path(token: contract.signing_token)

    expect(response.body).to include("Signing as")
    expect(response.body).to include("Katie Rae")
    expect(response.body).not_to include('id="signer_name"') # no typing field for a member
  end

  it "shows name/email fields to an anonymous signer" do
    get sign_contract_path(token: contract.signing_token)

    expect(response.body).to include('id="signer_name"')
    expect(response.body).not_to include("Signing as")
  end
end
