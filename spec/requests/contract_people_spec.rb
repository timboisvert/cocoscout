# frozen_string_literal: true

require "rails_helper"

# Contract people (docs/contract_people_plan.md, Tim 2026-10-17): the people
# a contractor brings get the contractor's visibility on My and nothing more.
# The Contractor stays the one party that signs and is paid. Nobody here is
# a production team member, and nothing of the organization's is theirs.
RSpec.describe "Contract people", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Carded", production_type: "third_party") }
  let(:dan) { create(:user, email_address: "dan@example.com", password: password) }
  let!(:dan_person) { create(:person, user: dan, name: "Dan Feltey", email: "dan@example.com").tap { |p| dan.update!(default_person: p) } }
  let!(:contractor) { create(:contractor, organization: org, name: "Carded LLC", email: "dan@example.com", person: dan_person) }
  let(:night) { 5.days.from_now.change(hour: 20, min: 0) }
  let!(:booth_role) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific) }
  let!(:booth) { org.house_services.create!(name: "Booth Tech", unit: "hourly").tap { |s| s.house_roles << booth_role } }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: "Carded LLC",
                      production_name: "Carded", shares_ticket_sales: true, draft_data: {
                        "payment_structure" => "revenue_share", "payment_config" => { "revenue_our_share" => 50, "revenue_their_share" => 50 },
                        "services" => [ { "name" => "Booth Tech", "service_id" => booth.id, "per_event" => true, "unit" => "hourly", "unit_price" => 25.0,
                                          "direction" => "incoming", "settlement" => "payout_deduction", "quantity" => 2.0,
                                          "events" => [ { "starts_at" => night.iso8601, "hours" => 2.0 } ] } ]
                      })
  end
  let!(:rental) { create(:space_rental, contract: contract, starts_at: night, ends_at: night + 3.hours) }
  let!(:show) { create(:show, production: production, space_rental: rental, date_and_time: night, duration_minutes: 120, event_type: "show") }
  let(:priya) { create(:user, email_address: "priya@example.com", password: password) }
  let!(:priya_person) { create(:person, user: priya, name: "Priya Nair", email: "priya@example.com").tap { |p| priya.update!(default_person: p) } }
  let!(:on_contract) { ContractPerson.create!(contract: contract, person: priya_person, added_by: owner) }

  before do
    contract.contract_payments.create!(description: "#{night.strftime('%b %-d')} — 50% to them", amount: 80, direction: "outgoing", due_date: night.to_date, show: show)
    contract.contract_payments.create!(description: "Booth Tech — #{night.strftime('%b %-d, %Y')}", amount: 50, direction: "incoming",
                                       settlement_method: "payout_deduction", due_date: night.to_date, show: show)
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def open_box_office
    TicketingProfile.for(org).update!(enabled: true)
    listing = create(:ticket_listing, organization: org, show: show)
    listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
    listing
  end

  it "shows a contract person the contract on My Contracts, with the money going to the contractor" do
    sign_in(priya)
    get my_contracts_path
    expect(response).to have_http_status(:ok)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Carded LLC", "Payments go to Carded LLC", "Coming to Carded LLC")
    expect(html).not_to include("Connect your bank", "Report sales", "Coming to you")

    sign_in(dan)
    get my_contracts_path
    expect(response.body).to include("Coming to you")
    expect(response.body).not_to include("Payments go to")
  end

  it "lists the date in My shows & events as theirs by contract, and reads the deal their way on its page" do
    sign_in(priya)
    get my_shows_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your contract", my_show_path(show))
    expect(response.body).not_to include("Can't make it")

    get my_show_path(show)
    expect(response).to have_http_status(:ok)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("data-contract-box", "Carded LLC", "50% of ticket sales", "$80.00", "−$50.00", "Booth Tech, 2 hrs", "You get", "$30.00",
                            "Payments go to Carded LLC.", my_contracts_path)
    expect(html).not_to include("They get", "Can't make it", "View contract")

    # The contractor's own person reads the same box, without being told where the money goes.
    sign_in(dan)
    get my_show_path(show)
    expect(response.body).to include("You get")
    expect(response.body).not_to include("Payments go to")
  end

  it "sees the date's sales on My Ticket Sales and gives comps for it, up to what the date can give" do
    listing = open_box_office
    sign_in(priya)
    get my_show_path(show)
    expect(response.body).to include("data-tickets-card", my_ticket_sale_path(listing), "and your comps,")

    get my_ticket_sale_path(listing)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your comps for this date", "Give comps", my_ticket_sale_comps_path(listing))

    expect { post my_ticket_sale_comps_path(listing), params: { name: "Abe Comp", quantity: "2", tier_id: listing.ticket_tiers.first.id } }
      .to change { Ticket.where(ticket_listing_id: listing.id).count }.by(2)
    expect(response).to redirect_to(my_ticket_sale_path(listing, anchor: "guests"))
    expect(flash[:notice]).to include("Gave 2 tickets to Abe Comp")

    # Once the date has started there are no comps to give.
    show.update_columns(date_and_time: 1.hour.ago)
    get my_ticket_sale_path(listing)
    expect(response.body).not_to include("Give comps")
  end

  it "never puts them on the production team or in the organization" do
    expect(priya.production_permissions).to be_empty
    expect(OrganizationRole.where(user: priya)).to be_empty
    expect(TicketSalesAccess.team_level_for(priya, production)).to be_nil
    expect(priya.reload.has_contracts?).to be(true)
  end

  it "stops seeing the sales when the contract says not" do
    listing = open_box_office
    contract.update!(shares_ticket_sales: false)
    sign_in(priya)
    get my_ticket_sale_path(listing)
    expect(response).not_to have_http_status(:ok)
    expect(TicketSalesAccess.comp_allowance(priya, listing)).to be_nil
  end

  it "shows the organization's managers who's on the contract: on the Productions list, on Who sees sales and on the contract" do
    open_box_office
    sign_in(owner)
    post set_organization_path(id: org.id)

    get manage_productions_path
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("data-contract-people", "Dan Feltey · on the contract with Carded LLC", "Priya Nair · on the contract with Carded LLC", manage_contract_path(contract))
    expect(html).not_to include("No production team assigned")

    get manage_production_ticketing_visibility_path(production)
    expect(response.body).to include("with Priya Nair")

    get manage_contract_path(contract)
    expect(CGI.unescapeHTML(response.body)).to include("On this contract", "Priya Nair", "Change who's on it", amend_people_manage_contract_path(contract))

    # The production's Team tab says the contractor's side isn't on it, and where they are.
    get edit_manage_production_path(production)
    html = CGI.unescapeHTML(response.body).gsub(/\s+/, " ")
    expect(html).to include("data-contract-people-panel", "Carded LLC", "sees this production through", "their contract</a>, not this team: Dan Feltey and Priya Nair.",
                            "Change who's on it", "Nobody from Stars & Garters on this team.")
    expect(html).not_to include("No production team members added yet")
  end

  it "adds, invites and removes people on a live contract at once, through Amend" do
    sam = create(:user, email_address: "sam@example.com", password: password)
    sam_person = create(:person, user: sam, name: "Sam Lee", email: "sam@example.com").tap { |p| sam.update!(default_person: p) }
    sign_in(owner)
    post set_organization_path(id: org.id)

    get amend_choose_manage_contract_path(contract)
    expect(response.body).to include("Change who's on it", amend_people_manage_contract_path(contract))

    get amend_people_manage_contract_path(contract)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Who's on this contract", "Dan Feltey", "The contractor", "Priya Nair", "Who else is on this contract?")

    post add_amend_person_manage_contract_path(contract), params: { person_id: sam_person.id }
    expect(flash[:notice]).to eq("Sam Lee is on the contract.")
    expect(contract.contract_people.map(&:person)).to contain_exactly(priya_person, sam_person)

    expect { post add_amend_person_manage_contract_path(contract), params: { email: "New@Example.org", name: "New Person" } }
      .to have_enqueued_mail(Manage::TeamMailer, :contract_invite)
    invitation = TeamInvitation.find_by(email: "new@example.org", contract: contract)
    expect(invitation).to be_present
    expect(flash[:notice]).to eq("Invited New Person. They're on the contract once they accept.")

    post add_amend_person_manage_contract_path(contract), params: { person_id: dan_person.id }
    expect(flash[:notice]).to eq("Dan Feltey is already on it.")

    delete remove_amend_person_manage_contract_path(contract), params: { person_id: priya_person.id }
    delete remove_amend_person_manage_contract_path(contract), params: { invitation_id: invitation.id }
    expect(contract.contract_people.reload.map(&:person)).to eq([ sam_person ])
    expect(TeamInvitation.where(contract: contract)).to be_empty

    # Dropped from the contract, Priya has no way to the date.
    sign_in(priya)
    get my_show_path(show)
    expect(response).to redirect_to(my_shows_path)
  end
end
