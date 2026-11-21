# frozen_string_literal: true

require "rails_helper"

# The comp rules (CompRules): Ticketing settings → Comps for the box office,
# a production's own on its Comps tab, a date's own on its Comps tab, and
# what they do to the manager's Comps tile.
RSpec.describe "Ticketing settings: Comps", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 3_000, quantity: 80) }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "shows the box office's three boxes with the defaults: allowed, no house limit, productions issue as many as they like, contractors none" do
    get manage_ticketing_settings_section_path(section: "comps")
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("[data-settings-card]").map { |card| card["data-settings-card"] }).to eq(%w[comps house-limit team-comps])
    expect(doc.text.squish).to include("House limit", "Productions and dates can't change it.", "Let productions issue their own comps",
                                       "What can productions on a contract issue?", "The settings above apply to them too.")
    expect(response.body).not_to include("per_performer", "One per performer")
    expect(response.body).to match(/id="ticketing_profile_comps_enabled"[^>]*checked/)
    expect(response.body).not_to match(/id="ticketing_profile_comps_limit"[^>]*checked/)
    expect(response.body).to match(/id="ticketing_profile_team_comps_limit_all"[^>]*checked/)
    # People on a contract start with none (Tim, 2026-11-17).
    expect(response.body).to match(/id="ticketing_profile_contract_choice_none"[^>]*checked/)
    # Each follow-up question names the answers it waits for (show-when).
    expect(doc.at_css("[data-comp-request-row='team']")["data-show-when-any"].split)
      .to contain_exactly("ticketing_profile_team_comps_limit_fixed", "ticketing_profile_team_comps_limit_day", "ticketing_profile_comps_limit")
  end

  it "saves the box office's rules, the house limit per show or per day" do
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: {
      comps_enabled: "1", comps_limit: "fixed", comps_per_show: "6", house_comps_period: "show", team_comps: "1", team_comps_limit: "fixed", team_comps_per_show: "2"
    } }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "comps"))
    profile = TicketingProfile.find_by!(organization: org)
    expect(flash[:notice]).to eq("Saved. Comps are allowed. The house limit is 6 per show. Productions may issue 2 per show. The same settings apply to productions on a contract.")
    expect(fresh_listing.comps_left).to eq(6)

    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: { comps_enabled: "1", comps_limit: "fixed", comps_per_show: "5", house_comps_period: "day" } }
    expect(profile.reload).to have_attributes(house_comps_period: "day", comps_per_show: 5)
    expect(flash[:notice]).to include("The house limit is 5 per day.")

    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: { comps_enabled: "0", comps_limit: "0", team_comps: "0", team_comps_limit: "all" } }
    expect(profile.reload).to have_attributes(comps_enabled: false, comps_limit: "unlimited")
    expect(fresh_listing.effective_comps_enabled).to be(false)
  end

  it "gives contracts a default of their own, or has them follow the production team's" do
    rules = { comps_enabled: "1", team_comps: "1", team_comps_limit: "fixed", team_comps_per_show: "2" }
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(contract_comps_own: "0", contract_comps: "1", contract_comps_limit: "day", contract_comps_per_show: "4") }
    expect(fresh_listing.comp_side_rules(:contract)).to have_attributes(issues: true, limit: "fixed", count: 2)

    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(contract_comps_own: "1", contract_comps: "1", contract_comps_limit: "day", contract_comps_per_show: "4") }
    expect(fresh_listing.comp_side_rules(:contract)).to have_attributes(issues: true, limit: "day", count: 4)
    expect(flash[:notice]).to end_with("Productions on a contract may issue 4 per day.")

    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(contract_comps_own: "1", contract_comps: "0", contract_comps_per_show: "4") }
    expect(fresh_listing.comp_side_rules(:contract).issues).to be(false)
    expect(flash[:notice]).to end_with("Productions on a contract can't issue comps themselves.")

    # Productions on a contract are a subset of productions: when productions
    # can't issue comps, neither can they, whatever their own limit says.
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(team_comps: "0", contract_comps_own: "1", contract_comps: "1") }
    expect(fresh_listing.comp_side_rules(:contract).issues).to be(false)
    expect(flash[:notice]).to end_with("Productions can't issue comps themselves.")

    # The form sends one question for contracts: the same, their own, or none.
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(contract_choice: "same") }
    expect(TicketingProfile.find_by!(organization: org).contract_comps_own).to be(false)
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(contract_choice: "own", contract_comps_limit: "fixed", contract_comps_per_show: "3") }
    expect(fresh_listing.comp_side_rules(:contract)).to have_attributes(issues: true, limit: "fixed", count: 3)
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(contract_choice: "none") }
    expect(TicketingProfile.find_by!(organization: org)).to have_attributes(contract_comps_own: true, contract_comps: false)

    # "One per performer" is no longer a rule: a form that still sends it gets the usual one.
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(comps_limit: "per_performer", team_comps_limit: "per_performer") }
    expect(TicketingProfile.find_by!(organization: org)).to have_attributes(comps_limit: "unlimited", team_comps_limit: "all")
  end

  # A listing that hasn't cached the rules from before a request (the spec's
  # instance would remember them).
  def fresh_listing
    TicketListing.find(listing.id)
  end

  it "lets a production have its own rules, and a date its own again, each following the level above when off" do
    setup = ProductionTicketing.for(production)
    TicketingProfile.for(org).update!(comps_limit: "fixed", comps_per_show: 20)

    get manage_edit_production_ticketing_path(production, section: "comps")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Override", "your box office&#39;s comps settings</a>", "for Stargazers", manage_ticketing_settings_section_path(section: "comps"))
    expect(response.body).to include("Allow comps on Stargazers", "Let Stargazers issue their own comps")
    # With the override off, the box office's answers are read out row by row.
    readout = Nokogiri::HTML(response.body).css("[data-comp-readout-row]").map { |row| row.text.squish }
    expect(readout).to eq([ "Allow comps on Stargazers Allowed", "Let Stargazers issue their own comps No limit",
                            "Let Stargazers request more when they run out Not allowed" ])
    # Only the box office sets the house limit.
    expect(response.body).not_to include("production_ticketing[comps_limit]", "House limit")

    patch manage_update_production_ticketing_path(production, section: "comps"), params: { production_ticketing: {
      own_comps: "1", comps_enabled: "1", team_comps: "1", team_comps_limit: "day", team_comps_per_show: "3"
    } }
    expect(response).to redirect_to(manage_edit_production_ticketing_path(production, section: "comps"))
    expect(setup.reload.own_comps).to be(true)
    expect(fresh_listing.comp_rules_source).to eq(:production)
    expect(fresh_listing.comp_side_rules(:team)).to have_attributes(limit: "day", count: 3)
    expect(fresh_listing.comps_left).to eq(20)
    expect(flash[:notice]).to eq("Saved. Stargazers has its own comp rules. Comps are allowed. Stargazers may issue 3 per day.")

    get manage_edit_ticket_listing_path(listing, section: "comps")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Stargazers&#39; comps settings</a>", "for this date", manage_edit_production_ticketing_path(production, section: "comps"))
    expect(Nokogiri::HTML(response.body).css("[data-comp-readout-row]").map { |row| row.text.squish })
      .to include("Let Stargazers issue their own comps 3 comps per day")
    expect(response.body).to include("How many can they issue on this date?")
    expect(response.body).not_to include("ticket_listing_team_comps_limit_day")

    patch manage_ticket_listing_path(listing, section: "comps"), params: { ticket_listing: { own_comps: "1", comps_enabled: "1", team_comps: "1", team_comps_limit: "fixed", team_comps_per_show: "5" } }
    expect(response).to redirect_to(manage_edit_ticket_listing_path(listing, section: "comps"))
    expect(fresh_listing.comp_rules_source).to eq(:listing)
    expect(flash[:notice]).to eq("Saved. This date has its own comp rules. Comps are allowed. Stargazers may issue 5 on this date.")

    patch manage_ticket_listing_path(listing, section: "comps"), params: { ticket_listing: { own_comps: "1", comps_enabled: "0" } }
    expect(fresh_listing.effective_comps_enabled).to be(false)

    # Switched off again, the date follows its production.
    patch manage_ticket_listing_path(listing, section: "comps"), params: { ticket_listing: { own_comps: "0" } }
    expect(fresh_listing.own_comps).to be(false)
    expect(fresh_listing.comps_enabled).to be_nil
    expect(fresh_listing.comp_side_rules(:team)).to have_attributes(limit: "day", count: 3)
    expect(flash[:notice]).to eq("Saved. This date follows Stargazers' comp rules.")

    patch manage_update_production_ticketing_path(production, section: "comps"), params: { production_ticketing: { own_comps: "0" } }
    expect(setup.reload.own_comps).to be(false)
    expect(setup.team_comps_limit).to be_nil
    expect(fresh_listing.comp_rules_source).to eq(:profile)
  end

  it "takes the Comps tile's modal away when comps are off or used up, and says where" do
    get manage_ticket_listing_path(listing)
    expect(response.body).to include('data-modal-id="comps-modal"', 'id="comps-modal"')

    listing.update!(own_comps: true, comps_enabled: false)
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Issued free · off on this date&#39;s Comps tab")
    expect(response.body).not_to include('data-modal-id="comps-modal"', 'id="comps-modal"')

    listing.update!(comps_enabled: true)
    TicketingProfile.for(org).update!(comps_limit: "fixed", comps_per_show: 1)
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Issued free · issue 1 more", 'id="comps-modal"')
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Abe Comp", email: nil, tier: general, quantity: 1) ], by: owner, email_them: false)
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Issued free · none left to issue")
    expect(response.body).not_to include('id="comps-modal"')
  end
end
