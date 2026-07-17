# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Contractors", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:contractor) { org.contractors.create!(name: "Sound Co", email: "sound@example.com") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers a bank-onboarding link when the backing person hasn't connected a bank" do
    get manage_contractor_path(contractor)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Getting paid").and include("Bank setup link")
    expect(response.body).to include("/pay/setup/")
  end

  it "shows the connected state once the backing person can receive payouts" do
    contractor.ensure_person!.update!(stripe_account_id: "acct_x", payouts_enabled: true)
    get manage_contractor_path(contractor)
    expect(response.body).to include("Bank connected")
    expect(response.body).not_to include("Bank setup link")
  end

  it "prompts to add an email when the contractor has none (can't back a person)" do
    emailless = org.contractors.create!(name: "No Email Co")
    get manage_contractor_path(emailless)
    expect(response.body).to include("Add an email")
    expect(response.body).not_to include("Bank setup link")
  end
end
