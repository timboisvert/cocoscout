# frozen_string_literal: true

require "rails_helper"

# A production's or a date's own Comps settings show only the side that
# applies (Tim, 2026-11-20): the contractor's for a production on a contract,
# the production team's for an in-house one, and both only for a contracted
# production that has production team managers of its own. One box, titled
# for the production; the side left out keeps its values when saved.
RSpec.describe "Comp settings on a production and a date", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, team_comps_limit: "fixed", team_comps_per_show: 2, team_comp_requests: true) } }

  let!(:in_house) { create(:production, organization: org, name: "Stargazers") }
  let!(:booked) { create(:production, organization: org, name: "It Left The Group Chat", production_type: "third_party") }
  let(:cora_person) { create(:person, name: "Cora Contractor") }
  let!(:contractor) { create(:contractor, organization: org, name: "Cora Contractor", person: cora_person) }
  let!(:contract) { create(:contract, :active, organization: org, production: booked, contractor: contractor, contractor_name: "Cora Contractor", production_name: booked.name, shares_ticket_sales: true) }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  def sides_on(path)
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("[data-settings-card]").map { |card| card["data-settings-card"] }).to eq(%w[comps])
    doc.css("[data-comp-side]").map { |side| side["data-comp-side"] }
  end

  it "shows the contractor's rules only on a production on a contract, in one box titled for it" do
    expect(sides_on(manage_edit_production_ticketing_path(booked, section: "comps"))).to eq(%w[contract])
    expect(response.body).to include("Comps for It Left The Group Chat", "Allow the contractor to issue comps", "Allow the contractor to request more comps when they run out")
    expect(response.body).not_to include("Your own productions", "Productions on a contract", "Allow production team managers to issue comps")
  end

  it "shows the production team's rules only on an in-house production" do
    expect(sides_on(manage_edit_production_ticketing_path(in_house, section: "comps"))).to eq(%w[team])
    expect(response.body).to include("Comps for Stargazers", "Allow production team managers to issue comps")
    expect(response.body).not_to include("Allow the contractor to issue comps", "Your own productions")
  end

  it "shows both on a production on a contract that has production team managers of its own" do
    co_producer = create(:user)
    ProductionPermission.create!(user: co_producer, production: booked, role: "manager")
    expect(sides_on(manage_edit_production_ticketing_path(booked, section: "comps"))).to eq(%w[contract team])
    expect(response.body).to include("The contractor", "Production team managers")
  end

  it "keeps the side it doesn't show when the production's own rules are saved" do
    patch manage_update_production_ticketing_path(booked, section: "comps"), params: { production_ticketing: {
      own_comps: "1", comps_enabled: "1", comps_limit: "unlimited", contract_comps: "1", contract_comps_per_show: "4", contract_comp_requests: "1",
      team_comps: "1", team_comps_limit: "fixed", team_comps_per_show: "2", team_comp_requests: "1"
    } }
    setup = ProductionTicketing.find_by!(production: booked)
    expect(setup).to have_attributes(own_comps: true, contract_comps_per_show: 4, contract_comp_requests: true,
                                     team_comps: true, team_comps_limit: "fixed", team_comps_per_show: 2, team_comp_requests: true)

    # What the page sends for the side it leaves out is what was there.
    get manage_edit_production_ticketing_path(booked, section: "comps")
    doc = Nokogiri::HTML(response.body)
    kept = doc.css("input[type=hidden][name^='production_ticketing[team_']").to_h { |input| [ input["name"], input["value"] ] }
    expect(kept).to include("production_ticketing[team_comps]" => "1", "production_ticketing[team_comps_limit]" => "fixed",
                            "production_ticketing[team_comps_per_show]" => "2", "production_ticketing[team_comp_requests]" => "1")
  end

  it "shows a date the side its production shows" do
    night = 5.days.from_now.change(hour: 20)
    rental = create(:space_rental, contract: contract, starts_at: night, ends_at: night + 3.hours)
    show = create(:show, production: booked, space_rental: rental, date_and_time: night)
    listing = create(:ticket_listing, organization: org, show: show)
    expect(sides_on(manage_edit_ticket_listing_path(listing, section: "comps"))).to eq(%w[contract])
    expect(response.body).to include("Comps for this date")

    in_house_listing = create(:ticket_listing, organization: org, show: create(:show, production: in_house, date_and_time: night))
    expect(sides_on(manage_edit_ticket_listing_path(in_house_listing, section: "comps"))).to eq(%w[team])
  end

  it "keeps all three boxes at the box office" do
    get manage_ticketing_settings_section_path(section: "comps")
    expect(Nokogiri::HTML(response.body).css("[data-settings-card]").map { |card| card["data-settings-card"] }).to eq(%w[comps team-comps contract-comps])
    expect(response.body).to include("Allow contractors to issue comps")
  end
end
