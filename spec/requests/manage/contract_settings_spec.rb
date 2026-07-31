# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ContractSettings", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "opens on the payments section, with a tab strip to the rest" do
    get manage_contract_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("How contractors may pay you")
    expect(response.body).to include(manage_contract_settings_section_path(section: "services"))
    # Sections load only their own data.
    expect(response.body).not_to include("Services catalog")
  end

  it "renders the services catalog in its own section" do
    org.contract_service_options.create!(name: "Technical services", default_price_cents: 2500, unit: "hourly")

    get manage_contract_settings_section_path(section: "services")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Services catalog")
    expect(response.body).to include("Technical services")
    expect(response.body).not_to include("How contractors may pay you")
  end

  it "sends an unknown section back to the default rather than blowing up" do
    get manage_contract_settings_section_path(section: "nonsense")

    expect(response).to redirect_to(manage_contract_settings_section_path(section: "payments"))
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

  describe "the notifications section" do
    let(:manager) { create(:user) }
    let!(:manager_role) { create(:organization_role, :manager, user: manager, organization: org) }

    it "lists the org's managers as notification recipients" do
      get manage_contract_settings_section_path(section: "notifications")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Contract signing alerts")
      expect(response.body).to include(manager.email_address)
    end

    it "saves the chosen recipients, ignoring non-managers" do
      patch manage_contract_settings_notifications_path,
        params: { notification_user_ids: [ manager.id.to_s, "999999" ] }

      expect(response).to redirect_to(manage_contract_settings_section_path(section: "notifications"))
      expect(org.reload.contract_notification_user_ids).to eq([ manager.id ])
    end

    it "clears recipients when none are ticked" do
      org.update!(contract_notification_user_ids: [ manager.id ])
      patch manage_contract_settings_notifications_path, params: {}
      expect(org.reload.contract_notification_user_ids).to eq([])
    end
  end
end
