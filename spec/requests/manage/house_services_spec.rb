# frozen_string_literal: true

require "rails_helper"

# The organization's services (after-V1 #6): defined once in Organization
# settings → Services with a default price and the roles that do each; Pro
# and managers only, and absent (no tab, no padlock) without Pro.
RSpec.describe "Organization services", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: manager) }
  let!(:foh) { create(:house_role, organization: org, name: "Front of House") }
  let!(:house_manager) { create(:house_role, organization: org, name: "House Manager") }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    get manage_path
  end

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    sign_in(manager)
  end

  it "lists the services with their roles, default price and contract terms" do
    tickets = org.house_services.create!(name: "Ticket taking", default_price_cents: 2500, offered_on_contracts: true)
    tickets.house_roles << [ foh, house_manager ]
    org.house_services.create!(name: "Projector rental", default_price_cents: 4000, offered_on_contracts: true, contract_price_cents: 5000)

    get section_manage_organization_path(org, section: "services")
    expect(response).to have_http_status(:ok)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Ticket taking", "Front of House", "House Manager", "$25.00 flat", "Offered",
                            "Projector rental", "No one: equipment or a fee", "Offered at $50.00 flat",
                            manage_contract_settings_section_path(section: "services"))
  end

  it "adds a service with the roles that do it, only ever the organization's own" do
    stranger = create(:house_role, name: "Elsewhere")
    expect {
      post manage_house_services_path, params: { house_service: {
        name: " Ticket taking ", default_price: "$25", unit: "flat", house_role_ids: [ "", foh.id, house_manager.id, stranger.id ]
      } }
    }.to change(HouseService, :count).by(1)

    service = org.house_services.last
    expect(service).to have_attributes(name: "Ticket taking", default_price_cents: 2500, unit: "flat", offered_on_contracts: false)
    expect(service.house_roles).to contain_exactly(foh, house_manager)
    expect(response).to redirect_to(section_manage_organization_path(org, section: "services"))
  end

  it "edits and removes one, and won't reach another organization's" do
    service = org.house_services.create!(name: "Booth Tech", default_price_cents: 2500, unit: "hourly")
    patch manage_house_service_path(service), params: { house_service: { name: "Booth Tech", default_price: "30", unit: "hourly", house_role_ids: [ "" ] } }
    expect(service.reload.default_price_cents).to eq(3000)

    theirs = create(:organization).house_services.create!(name: "Theirs")
    patch manage_house_service_path(theirs), params: { house_service: { name: "Mine now" } }
    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.name).to eq("Theirs")

    expect { delete manage_house_service_path(service) }.to change(HouseService, :count).by(-1)
  end

  it "says why a duplicate name didn't save" do
    org.house_services.create!(name: "Booth Tech")
    post manage_house_services_path, params: { house_service: { name: "booth tech", default_price: "1", unit: "flat" } }
    expect(flash[:alert]).to include("Name has already been taken")
  end

  context "without Pro" do
    before { org.update!(comped_indefinitely: false, comped_until: nil) }

    it "has no Services tab at all, and its URL goes back to the organization" do
      get manage_organization_path(org)
      expect(response.body).not_to include(section_manage_organization_path(org, section: "services"))

      get section_manage_organization_path(org, section: "services")
      expect(response).to redirect_to(manage_organization_path(org))

      post manage_house_services_path, params: { house_service: { name: "Booth Tech" } }
      expect(response).to have_http_status(:payment_required)
      expect(HouseService.count).to eq(0)
    end
  end

  it "keeps a production-team member who isn't a manager out" do
    member = create(:user, password: password)
    create(:organization_role, user: member, organization: org, company_role: "member")
    ProductionPermission.create!(user: member, production: create(:production, organization: org), role: "manager")
    post handle_signin_path, params: { email_address: member.email_address, password: password }
    post set_organization_path(id: org.id)

    post manage_house_services_path, params: { house_service: { name: "Booth Tech" } }
    expect(response).to redirect_to(manage_path)
    expect(flash[:notice]).to eq("That part of CocoScout is for your organization's managers.")
    expect(HouseService.count).to eq(0)
  end

  it "feeds the contract's Services step only what's offered, and the saved line names its service" do
    offered = org.house_services.create!(name: "Booth Tech", default_price_cents: 2500, unit: "hourly", offered_on_contracts: true, contract_price_cents: 3000)
    org.house_services.create!(name: "Videographer", default_price_cents: 4000, offered_on_contracts: false)
    contract = create(:contract, organization: org)

    get manage_tech_contract_wizard_path(contract)
    expect(response.body).to include("Booth Tech", "$30.00", %(name="services[0][service_id]" value="#{offered.id}"))
    expect(response.body).not_to include("Videographer")

    post manage_tech_contract_wizard_path(contract), params: { services: { "0" => {
      include: "1", service_id: offered.id.to_s, name: "Booth Tech", unit: "hourly", per_event: "0", quantity: "2", unit_price: "30", direction: "incoming", settlement: "direct"
    } } }
    expect(contract.reload.draft_services).to eq([ { "name" => "Booth Tech", "service_id" => offered.id, "unit" => "hourly",
                                                    "unit_price" => 30.0, "direction" => "incoming", "settlement" => "direct", "quantity" => 2.0 } ])
  end
end
