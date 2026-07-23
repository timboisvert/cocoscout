# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ContractWizard reordered flow", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:contract) do
    create(:contract, organization: org, status: :draft, wizard_step: 7,
                      contract_start_date: Date.current, contract_end_date: Date.current + 7.days,
                      draft_data: {
                        "bookings" => [
                          { "location_id" => location.id, "starts_at" => 1.day.from_now.iso8601,
                            "ends_at" => (1.day.from_now + 2.hours).iso8601 }
                        ]
                      })
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders each step of the new flow" do
    { bookings: :manage_bookings_contract_wizard_path,
      schedule_preview: :manage_schedule_preview_contract_wizard_path,
      deal: :manage_payments_contract_wizard_path,
      services: :manage_tech_contract_wizard_path,
      documents: :manage_documents_contract_wizard_path,
      review: :manage_review_contract_wizard_path }.each do |_name, helper|
      get public_send(helper, contract)
      expect(response).to have_http_status(:ok), "expected #{helper} to render"
    end
  end

  it "the financials step is titled 'Financials' and asks who sells, with Services next" do
    get manage_payments_contract_wizard_path(contract)
    expect(response.body).to include("Financials")
    expect(response.body).to include("Who sells the tickets?")
    expect(response.body).to include("Next: Services")
  end

  it "the services step replaces Tech and is skippable" do
    get manage_tech_contract_wizard_path(contract)
    expect(response.body).to include("Services")
    expect(response.body).to include("Skip — no services")
    expect(response.body).not_to include(">Tech<")
  end

  it "reorders the redirect chain: schedule → financials → services → documents → review" do
    # schedule preview → the deal
    post manage_schedule_preview_contract_wizard_path(contract)
    expect(response).to redirect_to(manage_payments_contract_wizard_path(contract))

    # the deal → services
    post manage_payments_contract_wizard_path(contract),
         params: { payments: [].to_json, payment_structure: "flat_fee", payment_config: {}.to_json }
    expect(response).to redirect_to(manage_tech_contract_wizard_path(contract))

    # services → documents
    post manage_tech_contract_wizard_path(contract), params: { tech_provider: "them" }
    expect(response).to redirect_to(manage_documents_contract_wizard_path(contract))
  end
end
