# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ContractSettings", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the services catalog" do
    org.contract_service_options.create!(name: "Technical services", default_price_cents: 2500, unit: "hourly")
    get manage_contract_settings_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Services catalog")
    expect(response.body).to include("Technical services")
  end

  it "adds a service (dollars → cents)" do
    expect {
      post manage_contract_settings_services_path, params: {
        contract_service_option: { name: "Booth tech", default_price: "40.00", unit: "hourly", default_direction: "incoming" }
      }
    }.to change(ContractServiceOption, :count).by(1)
    expect(org.contract_service_options.last.default_price_cents).to eq(4000)
  end

  it "updates a service" do
    svc = org.contract_service_options.create!(name: "Tech", default_price_cents: 2500, unit: "hourly")
    patch manage_contract_settings_service_path(svc), params: {
      contract_service_option: { name: "Tech", default_price: "30", unit: "hourly", default_direction: "incoming" }
    }
    expect(svc.reload.default_price_cents).to eq(3000)
  end

  it "removes a service" do
    svc = org.contract_service_options.create!(name: "Tech", default_price_cents: 2500, unit: "hourly")
    expect {
      delete manage_contract_settings_service_path(svc)
    }.to change(ContractServiceOption, :count).by(-1)
  end
end
