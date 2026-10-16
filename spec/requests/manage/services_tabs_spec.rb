# frozen_string_literal: true

require "rails_helper"

# The Services tabs (after-V1 #6): a production says what every show needs, a
# show can differ (one show or its whole series), and each level links back up.
RSpec.describe "Production and show Services tabs", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: manager) }
  let(:production) { create(:production, organization: org, name: "Halloween o' Weens") }
  let!(:booth) { org.house_services.create!(name: "Booth Tech", position: 0).tap { |s| s.house_roles << create(:house_role, organization: org, name: "Booth Tech") } }
  let!(:security) { org.house_services.create!(name: "Security", position: 1).tap { |s| s.house_roles << create(:house_role, organization: org, name: "Security") } }

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_path
  end

  def tab_labels(body)
    body.scan(/data-index="(\d+)"[^>]*>\s*([A-Z][A-Za-z ]+)/).map { |index, label| [ index.to_i, label.strip ] }
  end

  describe "on the production" do
    it "sits after Tickets, saves what every show needs, and lists the shows that differ" do
      get edit_manage_production_path(production)
      expect(tab_labels(response.body)).to include([ 7, "Tickets" ], [ 8, "Services" ], [ 9, "Danger Zone" ])
      expect(response.body).to include("What every show needs", section_manage_organization_path(org, section: "services"))

      patch update_services_manage_production_path(production), params: { needs: {
        booth.id.to_s => { needed: "1", people: "1" }, security.id.to_s => { needed: "1", people: "2" }
      } }
      expect(response).to redirect_to(edit_manage_production_path(production, tab: 8))
      expect(production.production_service_needs.map { |n| [ n.house_service.name, n.people_count ] }).to contain_exactly([ "Booth Tech", 1 ], [ "Security", 2 ])

      show = create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 20))
      ShowServices.change!(show, security, needed: false)
      get edit_manage_production_path(production)
      expect(response.body).to include("No Security", manage_edit_show_path(production, show, tab: 6))

      patch update_services_manage_production_path(production), params: { needs: { security.id.to_s => { needed: "0", people: "1" } } }
      expect(production.production_service_needs.reload.map { |n| n.house_service.name }).to eq([ "Booth Tech" ])
    end

    it "shows a contracted production's contract services, then the extras it doesn't bill" do
      contracted = create(:production, organization: org, name: "Nuns4Fun", production_type: "third_party")
      contract = create(:contract, :active, organization: org, production: contracted, contractor_name: "Nuns4Fun Entertainment",
                        draft_data: { "services" => [ { "name" => "Booth Tech", "service_id" => booth.id, "unit" => "hourly", "unit_price" => 25.0, "direction" => "incoming" } ] })

      get edit_manage_production_path(contracted)
      expect(tab_labels(response.body)).to include([ 4, "Tickets" ], [ 5, "Services" ], [ 6, "Danger Zone" ])
      html = response.body.gsub(/\s+/, " ")
      expect(html).to include("From the contract", "Your contract with Nuns4Fun Entertainment", "$25.00/hr · they pay us",
                              amend_choose_manage_contract_path(contract), "Also needed, not billed")
    end

    it "isn't there without Pro, and won't save" do
      org.update!(comped_indefinitely: false)
      get edit_manage_production_path(production)
      expect(response.body).not_to include("What every show needs")
      patch update_services_manage_production_path(production), params: { needs: { booth.id.to_s => { needed: "1", people: "1" } } }
      expect(production.production_service_needs).to be_empty
    end
  end

  describe "on a show" do
    let(:group) { SecureRandom.uuid }
    let!(:show) { create(:show, production: production, date_and_time: 8.days.from_now.change(hour: 20), recurrence_group_id: group) }
    let!(:next_week) { create(:show, production: production, date_and_time: 15.days.from_now.change(hour: 20), recurrence_group_id: group) }

    before { production.production_service_needs.create!(house_service: security) }

    def save_services(scope)
      patch manage_show_path(production, show), params: {
        show: { recurrence_edit_scope: scope },
        show_services: { booth.id.to_s => { needed: "1", people: "1" }, security.id.to_s => { needed: "0", people: "1" } }
      }
    end

    it "has its own Services tab, linking up to the production's" do
      get manage_edit_show_path(production, show)
      expect(response.body).to include("What this show needs", "Every Halloween o&#39; Weens show needs Security",
                                       "From the production", edit_manage_production_path(production, tab: 8))
    end

    it "changes this show only, or the whole series with the switch on" do
      save_services("this")
      expect(ShowServices.new([ show ]).for(show).map { |n| [ n.service.name, n.dropped ] }).to eq([ [ "Booth Tech", false ], [ "Security", true ] ])
      expect(next_week.show_service_changes).to be_empty

      save_services("all")
      expect(next_week.show_service_changes.reload.map { |c| [ c.house_service.name, c.needed ] }).to contain_exactly([ "Booth Tech", true ], [ "Security", false ])
    end
  end

  it "ticks a new contract's services the production's shows already need" do
    booth.update!(offered_on_contracts: true)
    production.production_service_needs.create!(house_service: booth)
    contract = create(:contract, organization: org, production: production)

    get manage_tech_contract_wizard_path(contract)
    expect(response.body.gsub(/\s+/, " ")).to include("Ticked for you: Halloween o&#39; Weens&#39; shows need Booth Tech.")
  end
end
