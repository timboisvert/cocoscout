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

  it "shows the five parts with the defaults: on, no limit, the team may issue all of them, people on a contract none" do
    get manage_ticketing_settings_section_path(section: "comps")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Comps per date", "Production team managers can issue comps", "How many of them a production team may issue",
                                     "People on a contract can issue comps", "shared between everyone on the contract",
                                     "With these rules, a date can issue as many comps as it has seats, its production team managers may issue any of them, and people on a contract issue none of them.")
    # Comps are none or a number: "one per performer" is not offered (Tim, 2026-11-17).
    expect(response.body).not_to include("per_performer", "One per performer")
    expect(response.body).not_to match(/id="ticketing_profile_contract_comps"[^>]*checked/)
    expect(response.body).to match(/id="ticketing_profile_comps_enabled"[^>]*checked/)
    expect(response.body).to match(/id="ticketing_profile_comps_limit_unlimited"[^>]*checked/)
    expect(response.body).to match(/id="ticketing_profile_team_comps_limit_all"[^>]*checked/)
    expect(response.body).to include('id="ticketing_profile_comps_per_show"', 'id="ticketing_profile_team_comps_per_show"', 'id="ticketing_profile_contract_comps_per_show"')
  end

  it "saves the box office's rules" do
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: {
      comps_enabled: "1", comps_limit: "fixed", comps_per_show: "6", team_comps: "1", team_comps_limit: "fixed", team_comps_per_show: "2"
    } }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "comps"))
    profile = TicketingProfile.find_by!(organization: org)
    expect(profile.comp_rules_words).to eq("comps on · 6 per date · production team managers may issue 2 of them · people on a contract don't issue them")
    expect(flash[:notice]).to eq("Saved. Comps on · 6 per date · production team managers may issue 2 of them · people on a contract don't issue them.")
    expect(fresh_listing.effective_comps_per_show).to eq(6)
    expect(fresh_listing.comps_left).to eq(6)

    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: { comps_enabled: "0", comps_limit: "unlimited", team_comps: "0", team_comps_limit: "all" } }
    expect(profile.reload.comps_enabled).to be(false)
    expect(fresh_listing.effective_comps_enabled).to be(false)
  end

  it "saves how many the people on a contract may issue, and none when it's switched off" do
    rules = { comps_enabled: "1", comps_limit: "unlimited", team_comps: "1", team_comps_limit: "all" }
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(contract_comps: "1", contract_comps_per_show: "4") }
    profile = TicketingProfile.find_by!(organization: org)
    expect(profile.contract_comps_per_show).to eq(4)
    expect(flash[:notice]).to end_with("people on a contract may issue 4 of them.")
    expect(fresh_listing.effective_contract_comps).to eq(4)

    get manage_ticketing_settings_section_path(section: "comps")
    expect(response.body).to match(/id="ticketing_profile_contract_comps"[^>]*checked/)
    expect(response.body).to include("and people on a contract may issue 4 of them.")

    # The number stays in the box, and the switch is what counts.
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(contract_comps: "0", contract_comps_per_show: "4") }
    expect(profile.reload.contract_comps_per_show).to eq(0)

    # "One per performer" is no longer a rule: a form that still sends it gets the usual one.
    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: rules.merge(comps_limit: "per_performer", team_comps_limit: "per_performer") }
    expect(profile.reload).to have_attributes(comps_limit: "unlimited", team_comps_limit: "all")
  end

  # A listing that hasn't cached the rules from before a request (the spec's
  # instance would remember them).
  def fresh_listing
    TicketListing.find(listing.id)
  end

  it "lets a production have its own rules, and a date its own again, each following the level above when off" do
    setup = ProductionTicketing.for(production)

    get manage_edit_production_ticketing_path(production, section: "comps")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Override", "your box office&#39;s comps settings</a>", "for Stargazers", manage_ticketing_settings_section_path(section: "comps"))

    patch manage_update_production_ticketing_path(production, section: "comps"), params: { production_ticketing: {
      own_comps: "1", comps_enabled: "1", comps_limit: "fixed", comps_per_show: "8", team_comps: "1", team_comps_limit: "all",
      contract_comps: "1", contract_comps_per_show: "3"
    } }
    expect(response).to redirect_to(manage_edit_production_ticketing_path(production, section: "comps"))
    expect(setup.reload.own_comps).to be(true)
    expect(fresh_listing.comp_rules_source).to eq(:production)
    expect(fresh_listing.effective_comps_per_show).to eq(8)
    expect(fresh_listing.effective_contract_comps).to eq(3)
    expect(flash[:notice]).to include("Stargazers has its own comp rules: comps on · 8 per date")

    get manage_edit_ticket_listing_path(listing, section: "comps")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Stargazers&#39; comps settings</a>", "for this date", manage_edit_production_ticketing_path(production, section: "comps"))

    patch manage_ticket_listing_path(listing, section: "comps"), params: { ticket_listing: { own_comps: "1", comps_enabled: "0" } }
    expect(response).to redirect_to(manage_edit_ticket_listing_path(listing, section: "comps"))
    expect(fresh_listing.comp_rules_source).to eq(:listing)
    expect(fresh_listing.effective_comps_enabled).to be(false)
    expect(fresh_listing.effective_contract_comps).to eq(0)

    # Switched off again, the date follows its production.
    patch manage_ticket_listing_path(listing, section: "comps"), params: { ticket_listing: { own_comps: "0" } }
    expect(fresh_listing.own_comps).to be(false)
    expect(fresh_listing.comps_enabled).to be_nil
    expect(fresh_listing.contract_comps_per_show).to be_nil
    expect(fresh_listing.effective_comps_per_show).to eq(8)
    expect(fresh_listing.effective_contract_comps).to eq(3)
    expect(flash[:notice]).to eq("Saved. This date follows Stargazers' comp rules.")

    patch manage_update_production_ticketing_path(production, section: "comps"), params: { production_ticketing: { own_comps: "0" } }
    expect(setup.reload.own_comps).to be(false)
    expect(setup.comps_limit).to be_nil
    expect(fresh_listing.comp_rules_source).to eq(:profile)
  end

  it "takes the Comps tile's modal away when comps are off or used up, and says where" do
    get manage_ticket_listing_path(listing)
    expect(response.body).to include('data-modal-id="comps-modal"', 'id="comps-modal"')

    listing.update!(own_comps: true, comps_enabled: false)
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Issued free · off on this date&#39;s Comps tab")
    expect(response.body).not_to include('data-modal-id="comps-modal"', 'id="comps-modal"')

    listing.update!(comps_enabled: true, comps_limit: "fixed", comps_per_show: 1)
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Issued free · issue 1 more", 'id="comps-modal"')
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Abe Comp", email: nil, tier: general, quantity: 1) ], by: owner, email_them: false)
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Issued free · none left to issue")
    expect(response.body).not_to include('id="comps-modal"')
  end
end
