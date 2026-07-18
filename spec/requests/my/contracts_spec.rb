# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Contracts", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:org) { create(:organization, :pro) }
  let(:contractor) { create(:contractor, organization: org, person: person, email: person.email) }
  let!(:contract) { create(:contract, :active, organization: org, contractor: contractor, contractor_name: "Sound Co") }
  let!(:payment) { create(:contract_payment, :outgoing, contract: contract, amount: 300, description: "First payment") }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "lists the contracts the signed-in person holds as a contractor" do
    get my_contracts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("My Contracts").and include("First payment")
  end

  it "renders a full-summary modal for each contract" do
    get my_contracts_path
    expect(response.body).to include("contract-modal-#{contract.id}")
    expect(response.body).to include("View full contract")
    # Modal frames the payment from the contractor's point of view.
    expect(response.body).to include("Your pay")
    expect(response.body).to include(org.name)
  end

  it "prompts to connect a bank when the person can't receive payouts yet" do
    get my_contracts_path
    expect(response.body).to include("Connect your bank")
  end

  it "doesn't show contracts belonging to a different person" do
    other = create(:contractor, organization: org, person: create(:person), email: "other@example.com")
    create(:contract, :active, organization: org, contractor: other, contractor_name: "Other Co")
    get my_contracts_path
    expect(response.body).not_to include("Other Co")
  end
end
