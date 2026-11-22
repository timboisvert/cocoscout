# frozen_string_literal: true

require "rails_helper"

# One message thread per contract (linked productions step 5; Tim,
# 2026-11-22): the organization's owner and managers, the contractor, and the
# people on the contract all write into it and read it in their own Messages.
RSpec.describe "Contract thread", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:owner_person) { create(:person, user: owner, name: "Tim Boisvert").tap { |p| owner.update!(default_person: p) } }
  let!(:production) { create(:production, organization: org, name: "Carded", production_type: "third_party") }
  let(:dan) { create(:user, password: password) }
  let!(:dan_person) { create(:person, user: dan, name: "Dan Feltey", email: dan.email_address).tap { |p| dan.update!(default_person: p) } }
  let!(:contractor) { create(:contractor, organization: org, name: "Carded LLC", email: dan.email_address, person: dan_person) }
  let!(:contract) { create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: "Carded LLC", production_name: "Carded") }
  let(:priya) { create(:user, password: password) }
  let!(:priya_person) { create(:person, user: priya, name: "Priya Nair", email: priya.email_address).tap { |p| priya.update!(default_person: p) } }
  let!(:on_contract) { ContractPerson.create!(contract: contract, person: priya_person, added_by: owner) }
  let(:stranger) { create(:user, password: password) }

  before { create(:organization_role, :manager, user: owner, organization: org) }

  def sign_in(user)
    get signout_path
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "starts the thread from the organization's side, reaches everyone on the contract, and takes replies from their side" do
    sign_in(owner)
    get manage_contract_path(contract)
    expect(response.body).to include("Messages about this contract", "data-contract-thread")

    post contract_thread_path(contract), params: { body: "Load-in is at 5 on Friday." }, headers: { "HTTP_REFERER" => manage_contract_url(contract) }
    root = ContractThread.root(contract)
    expect(response).to redirect_to(manage_contract_url(contract))
    expect(root.subject).to include("Carded")
    expect(root.subscribers).to include(owner, dan, priya)

    sign_in(priya)
    get my_contracts_path
    expect(response.body).to include("Messages about this contract", "Load-in is at 5 on Friday.")
    post contract_thread_path(contract), params: { body: "Thanks, we'll be there." }
    expect(ContractThread.root(contract)).to eq(root)
    expect(root.child_messages.last.body.to_plain_text).to include("we'll be there")
  end

  it "takes nothing from someone who isn't on the contract, and nothing empty" do
    sign_in(stranger)
    post contract_thread_path(contract), params: { body: "Hello" }
    expect(response).to have_http_status(:not_found)

    sign_in(dan)
    post contract_thread_path(contract), params: { body: "  " }
    expect(flash[:alert]).to eq("Write a message first.")
    expect(ContractThread.root(contract)).to be_nil
  end
end
