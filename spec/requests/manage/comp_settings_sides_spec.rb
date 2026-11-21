# frozen_string_literal: true

require "rails_helper"

# A production's or a date's own Comps settings (Tim, 2026-11-21): one box,
# titled for the production, with its own questions by name and, only when it
# is on a contract, the contractor's inside them. Productions on a contract
# are a subset of productions, not peers, at every level. A production that
# isn't on a contract keeps the contract's values when saved.
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

  def comps_box(path)
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("[data-settings-card]").map { |card| card["data-settings-card"] }).to eq(%w[comps])
    doc.at_css("[data-settings-card='comps']")
  end

  it "asks about the contractor, by name, inside the production's questions on a production on a contract" do
    box = comps_box(manage_edit_production_ticketing_path(booked, section: "comps"))
    expect(box["data-comp-contracted"]).to eq("yes")
    block = box.at_css("[data-comp-contract-block]")
    expect(block["data-show-when"]).to eq("production_ticketing_team_comps")
    expect(box.text.squish).to include("Comps for It Left The Group Chat", "Let It Left The Group Chat issue their own comps",
                                       "What can Cora Contractor issue?", "The same as above", "A limit of their own")
    expect(response.body).not_to include("House limit", "ticketing_profile")
  end

  it "asks nothing about a contract on an in-house production" do
    box = comps_box(manage_edit_production_ticketing_path(in_house, section: "comps"))
    expect(box["data-comp-contracted"]).to eq("no")
    expect(box.at_css("[data-comp-contract-block]")).to be_nil
    expect(box.text.squish).to include("Comps for Stargazers", "Let Stargazers issue their own comps")
  end

  it "keeps the contract's values on a production that isn't on one when its own rules are saved" do
    ProductionTicketing.for(in_house).update!(own_comps: true, contract_comps_own: true, contract_comps: true, contract_comps_per_show: 5)
    get manage_edit_production_ticketing_path(in_house, section: "comps")
    kept = Nokogiri::HTML(response.body).css("input[type=hidden][name^='production_ticketing[contract_']").to_h { |input| [ input["name"], input["value"] ] }
    expect(kept).to include("production_ticketing[contract_comps_own]" => "1", "production_ticketing[contract_comps]" => "1",
                            "production_ticketing[contract_comps_per_show]" => "5")
  end

  it "gives the contractor nothing when the production can't issue comps, whatever their own limit says" do
    patch manage_update_production_ticketing_path(booked, section: "comps"), params: { production_ticketing: {
      own_comps: "1", comps_enabled: "1", team_comps: "0", contract_comps_own: "1", contract_comps: "1", contract_comps_per_show: "4"
    } }
    setup = ProductionTicketing.find_by!(production: booked)
    expect(setup).to have_attributes(own_comps: true, team_comps: false, contract_comps_own: true, contract_comps: true)
    expect(setup.comp_side(:contract).issues).to be(false)
    expect(flash[:notice]).to eq("Saved. It Left The Group Chat has its own comp rules. Comps are allowed. It Left The Group Chat can't issue comps themselves.")

    patch manage_update_production_ticketing_path(booked, section: "comps"), params: { production_ticketing: {
      own_comps: "1", comps_enabled: "1", team_comps: "1", team_comps_limit: "fixed", team_comps_per_show: "6", contract_comps_own: "0"
    } }
    expect(setup.reload.comp_side(:contract)).to have_attributes(issues: true, limit: "fixed", count: 6)
    expect(flash[:notice]).to end_with("It Left The Group Chat may issue 6 per show. The same settings apply to Cora Contractor.")
  end

  it "asks a date about its contractor the way its production does" do
    night = 5.days.from_now.change(hour: 20)
    rental = create(:space_rental, contract: contract, starts_at: night, ends_at: night + 3.hours)
    show = create(:show, production: booked, space_rental: rental, date_and_time: night)
    listing = create(:ticket_listing, organization: org, show: show)
    box = comps_box(manage_edit_ticket_listing_path(listing, section: "comps"))
    expect(box["data-comp-contracted"]).to eq("yes")
    expect(box.text.squish).to include("Comps for this date", "What can Cora Contractor issue?")

    in_house_listing = create(:ticket_listing, organization: org, show: create(:show, production: in_house, date_and_time: night))
    expect(comps_box(manage_edit_ticket_listing_path(in_house_listing, section: "comps"))["data-comp-contracted"]).to eq("no")
  end

  it "puts productions on a contract inside Your productions at the box office" do
    get manage_ticketing_settings_section_path(section: "comps")
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("[data-settings-card]").map { |card| card["data-settings-card"] }).to eq(%w[comps house-limit team-comps])
    block = doc.at_css("[data-settings-card='team-comps'] [data-comp-contract-block]")
    expect(block["data-show-when"]).to eq("ticketing_profile_team_comps")
    expect(block.text.squish).to include("What can productions on a contract issue?", "The same as above", "A limit of their own", "None")
  end
end
