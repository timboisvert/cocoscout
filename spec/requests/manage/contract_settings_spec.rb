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
    expect(response.body).not_to include("Offered on contracts")
  end

  it "lists the organization's services to offer on contracts, in its own section" do
    org.house_services.create!(name: "Technical services", default_price_cents: 2500, unit: "hourly")

    get manage_contract_settings_section_path(section: "services")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Offered on contracts", "Technical services", "Default: $25.00/hr",
                                     section_manage_organization_path(org, section: "services"))
    expect(response.body).not_to include("How contractors may pay you")
  end

  it "sends an unknown section back to the default rather than blowing up" do
    get manage_contract_settings_section_path(section: "nonsense")

    expect(response).to redirect_to(manage_contract_settings_section_path(section: "payments"))
  end

  describe "invoices" do
    it "shows the next number and what invoices will say, falling back to what CocoScout knows" do
      org.update!(name: "Stars & Garters")

      get manage_contract_settings_section_path(section: "invoices")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("SG-0001", "Stars &amp; Garters", owner.email_address)
    end

    it "saves the prefix and only the details someone typed" do
      patch manage_contract_settings_invoices_path, params: {
        invoice_prefix: "sng", invoice_details: { name: "", address: "1 Main St\nChicago, IL", note: "Checks to S&G LLC" }
      }

      expect(response).to redirect_to(manage_contract_settings_section_path(section: "invoices"))
      expect(org.reload.invoice_prefix).to eq("SNG")
      expect(org.invoice_details).to eq("address" => "1 Main St\nChicago, IL", "note" => "Checks to S&G LLC")
      expect(org.invoice_seller.name).to eq(org.name)
    end

    it "refuses a prefix that isn't letters and numbers" do
      patch manage_contract_settings_invoices_path, params: { invoice_prefix: "S&G!" }

      expect(flash[:alert]).to include("letters and numbers")
      expect(org.reload.invoice_prefix).to be_nil
    end
  end

  it "chooses which services contracts offer and their terms; a blank price is the default" do
    tech = org.house_services.create!(name: "Booth Tech", default_price_cents: 2500, unit: "hourly")
    security = org.house_services.create!(name: "Security", default_price_cents: 5000, offered_on_contracts: true, contract_price_cents: 4000)

    patch manage_contract_settings_services_path, params: { services: {
      tech.id.to_s => { offered: "1", price: "", direction: "incoming", booking_mode: "per_event" },
      security.id.to_s => { offered: "0", price: "60", direction: "outgoing", booking_mode: "once" }
    } }

    expect(response).to redirect_to(manage_contract_settings_section_path(section: "services"))
    expect(tech.reload).to have_attributes(offered_on_contracts: true, contract_price_cents: nil, contract_booking_mode: "per_event")
    expect(tech.contract_price_cents_or_default).to eq(2500)
    expect(security.reload).to have_attributes(offered_on_contracts: false, contract_price_cents: 6000, contract_direction: "outgoing")
  end

  it "never touches another organization's services" do
    theirs = create(:organization).house_services.create!(name: "Theirs", offered_on_contracts: false)
    patch manage_contract_settings_services_path, params: { services: { theirs.id.to_s => { offered: "1" } } }
    expect(theirs.reload.offered_on_contracts).to be(false)
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
