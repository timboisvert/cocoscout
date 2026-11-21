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
  let!(:owner_person) { create(:person, user: owner, name: "Tim Boisvert").tap { |p| owner.update!(default_person: p) } }
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
    # None of our casting on a contract date (Tim, 2026-10-18): no availability to give, no cast; the
    # question goes to the organization, not "the team".
    expect(html).not_to include("My Availability", "Full Cast", "Running Order", "Contact Team")
    expect(html).to include("Contact Stars &amp; Garters", "Have a question about this date?")

    post my_production_production_messages_path(production), params: { subject: "Door time?", body: "What time can we load in?" }
    expect(response).to redirect_to(my_messages_path)
    expect(Message.order(:id).last.subject).to eq("Door time?")
    expect(Message.order(:id).last.recipient_people).to include(owner_person)

    # The contractor's own person reads the same box, without being told where the money goes.
    sign_in(dan)
    get my_show_path(show)
    expect(response.body).to include("You get")
    expect(response.body).not_to include("Payments go to")
  end

  it "can look back at the contract's dates that have happened, newest first" do
    earlier = 10.days.ago.change(hour: 20)
    old_rental = create(:space_rental, contract: contract, starts_at: earlier, ends_at: earlier + 3.hours)
    old_show = create(:show, production: production, space_rental: old_rental, date_and_time: earlier, event_type: "show")
    older = 20.days.ago.change(hour: 20)
    older_rental = create(:space_rental, contract: contract, starts_at: older, ends_at: older + 3.hours)
    older_show = create(:show, production: production, space_rental: older_rental, date_and_time: older, event_type: "show")

    sign_in(priya)
    get my_shows_path
    expect(response.body).to include(">Upcoming<", ">Past<", my_show_path(show))
    expect(response.body).not_to include(my_show_path(old_show), "By Production")

    get my_shows_path(when: "past")
    expect(response).to have_http_status(:ok)
    html = response.body
    expect(html).to include(my_show_path(old_show), my_show_path(older_show), "Your contract")
    expect(html).not_to include(my_show_path(show))
    expect(html.index(my_show_path(old_show))).to be < html.index(my_show_path(older_show))
  end

  it "issues comps from a pasted list on the date's Tickets page, the whole list or none" do
    listing = open_box_office
    TicketingProfile.for(org).update!(contract_comps_own: true, contract_comps: true, contract_comps_per_show: 3)
    general = listing.ticket_tiers.first
    sign_in(priya)
    get my_show_tickets_path(listing.show)
    expect(response.body).to include("Paste a list", my_show_ticket_comps_preview_path(listing.show))

    post my_show_ticket_comps_preview_path(listing.show), params: { tier_id: general.id, text: "Abe Comp, abe@example.com, 2\nBea Comp" }
    expect(response.body).to include('data-comps-paste-ready="3"', "Abe Comp", "Bea Comp")

    expect { post my_show_ticket_comps_path(listing.show), params: { mode: "paste", tier_id: general.id, text: "Abe Comp, 2\nBea Comp, bea@example" } }
      .not_to change { Ticket.where(ticket_listing_id: listing.id).count }
    expect(flash[:alert]).to eq("Line 2: bea@example isn't an email address.")

    expect { post my_show_ticket_comps_path(listing.show), params: { mode: "paste", tier_id: general.id, text: "Abe Comp, abe@example.com, 2\nBea Comp" } }
      .to change { Ticket.where(ticket_listing_id: listing.id).count }.by(3)
    expect(response).to redirect_to(my_show_tickets_path(listing.show, anchor: "guests"))
    expect(flash[:notice]).to eq("Issued 3 tickets to 2 people. They're on the guest list.")

    # The contract's three are given: a list of one more is turned away.
    post my_show_ticket_comps_path(listing.show), params: { mode: "paste", tier_id: general.id, text: "Cy Comp" }
    expect(flash[:alert]).to eq("You can't issue comps for this date.")
  end

  it "sees the date's sales on its Tickets page under the show and issues comps for it, up to the number the organization allows the people on a contract" do
    listing = open_box_office
    sign_in(priya)
    get my_show_path(show)
    expect(response.body).to include("data-tickets-card", my_show_tickets_path(listing.show), "View ticket sales")

    # People on a contract start with none (Tim, 2026-11-17): the page shows the sales and no comps.
    get my_show_tickets_path(listing.show)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("data-comps-box", "Issue comps")
    expect { post my_show_ticket_comps_path(listing.show), params: { name: "Abe Comp", quantity: "1", tier_id: listing.ticket_tiers.first.id } }
      .not_to(change { Ticket.where(ticket_listing_id: listing.id).count })

    # The box office allows three per date, between everyone on the contract.
    TicketingProfile.for(org).update!(contract_comps_own: true, contract_comps: true, contract_comps_per_show: 3)
    get my_show_tickets_path(listing.show)
    expect(response.body).to include(my_show_ticket_comps_path(listing.show))
    expect(Nokogiri::HTML(response.body).at_css("[data-comps-box]")&.text.to_s.squish).to match(/Issue comps.*For this date\s*3\s*Shared by everyone on the contract.*Issued\s*0.*Left to issue\s*3/)

    expect { post my_show_ticket_comps_path(listing.show), params: { name: "Abe Comp", quantity: "2", tier_id: listing.ticket_tiers.first.id } }
      .to change { Ticket.where(ticket_listing_id: listing.id).count }.by(2)
    expect(response).to redirect_to(my_show_tickets_path(listing.show, anchor: "guests"))
    expect(flash[:notice]).to include("Issued 2 tickets to Abe Comp")

    # One number between them: the contractor has what Priya left, and no more.
    expect(TicketSalesAccess.comp_allowance(dan, TicketListing.find(listing.id))).to include(team_limit: 3, team_given: 2, left: 1, contract: true)
    get my_show_tickets_path(listing.show)
    expect(Nokogiri::HTML(response.body).at_css("[data-comps-box]")&.text.to_s.squish).to match(/Issued\s*2.*Left to issue\s*1/)
    expect { post my_show_ticket_comps_path(listing.show), params: { name: "Bea Comp", quantity: "2", tier_id: listing.ticket_tiers.first.id } }
      .not_to(change { Ticket.where(ticket_listing_id: listing.id).count })
    expect(flash[:alert]).to eq("You can issue 1 more comp for this date.")
    # Their comps are their own number's, not the production team's share.
    expect(TicketSalesAccess.contract_comps_given(listing)).to eq(2)
    expect(TicketSalesAccess.team_comps_given(listing)).to eq(0)

    # Once the date has started there are no comps to give.
    show.update_columns(date_and_time: 1.hour.ago)
    get my_show_tickets_path(listing.show)
    expect(response.body).not_to include("Issue comps")

    # And the date's page says it has happened, with the way into how it sold and no link to share (Tim, 2026-10-18).
    get my_show_path(show)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include('data-show-state="past"', "has already happened", my_show_tickets_path(listing.show), "View ticket sales")
    expect(html).not_to include("Your link for this date", "Who's coming is in", "Who's coming, and your comps")
  end

  # Tim, 2026-11-17: the side that issued a comp can change the guest's name or take it back; it doesn't matter who on it did.
  it "lets them edit and remove a comp the contract's side issued, never the organization's own or a sale" do
    listing = open_box_office
    TicketingProfile.for(org).update!(contract_comps_own: true, contract_comps: true, contract_comps_per_show: 3)
    tier = listing.ticket_tiers.first
    sign_in(priya)
    post my_show_ticket_comps_path(listing.show), params: { name: "Abe Comp", quantity: "2", tier_id: tier.id }
    mine = listing.ticket_orders.find_by!(buyer_name: "Abe Comp")
    # One the contractor issued, one the organization's own manager issued, and one somebody bought.
    dans = TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Dan's Guest", email: nil, tier: tier, quantity: 1) ], by: dan, email_them: false).sole
    houses = TicketComps.give!(listing, [ TicketComps::Guest.new(name: "House Guest", email: nil, tier: tier, quantity: 1) ], by: owner, email_them: false).sole
    bought = create(:ticket_order, organization: org, ticket_listing: listing, status: "paid", buyer_name: "Paying Buyer")
    bought.tickets.create!(ticket_tier: tier, ticket_listing: listing, status: "valid", price_cents: 2_000)

    get my_show_tickets_path(listing.show)
    html = response.body
    expect(html).to include("Edit or remove this comp", "edit-comp-#{mine.id}", "remove-comp-#{mine.id}", my_show_ticket_comp_path(listing.show, mine.id),
                            "edit-comp-#{dans.id}")
    expect(html).not_to include("edit-comp-#{houses.id}", "edit-comp-#{bought.id}", "You issued this")

    # Issued without an email: the Email them their tickets switch is there, off, as when a comp is issued.
    expect(html).to include("edit_comp_email_them_#{mine.id}", "They haven't been emailed their tickets yet.")
    expect(html).not_to match(/id="edit_comp_email_them_#{mine.id}"[^>]*checked/)

    # Switch left off: the name changes and no email is kept or sent, whatever was typed.
    expect { patch my_show_ticket_comp_path(listing.show, mine.id), params: { name: "Abe Corrected", email_them: "0" } }
      .not_to have_enqueued_job(TicketOrderConfirmationJob)
    expect(response).to redirect_to(my_show_tickets_path(listing.show, anchor: "guests"))
    expect(mine.reload).to have_attributes(buyer_name: "Abe Corrected", buyer_email: nil)
    expect(flash[:notice]).to eq("Saved. The comp is for Abe Corrected now.")

    # Switched on, their email is needed, and the tickets go to it.
    patch my_show_ticket_comp_path(listing.show, mine.id), params: { name: "Abe Corrected", email_them: "1", email: "" }
    expect(flash[:alert]).to eq("Add their email to send their tickets, or switch off Email them their tickets.")
    expect { patch my_show_ticket_comp_path(listing.show, mine.id), params: { name: "Abe Corrected", email_them: "1", email: "abe@example.com" } }
      .to have_enqueued_job(TicketOrderConfirmationJob).with(mine.id)
    expect(mine.reload.buyer_email).to eq("abe@example.com")
    expect(flash[:notice]).to eq("Saved. The comp is for Abe Corrected now. Their tickets are on the way to abe@example.com.")

    # Now the comp has an email: no switch, the email is required, and only a new address gets the tickets again.
    get my_show_tickets_path(listing.show)
    expect(response.body).to include("Their tickets were emailed to this address.")
    expect(response.body).not_to include("edit_comp_email_them_#{mine.id}")
    patch my_show_ticket_comp_path(listing.show, mine.id), params: { name: "Abe Corrected", email: "" }
    expect(flash[:alert]).to eq("Add their email. Their tickets were sent to abe@example.com, so this comp needs an address.")
    expect { patch my_show_ticket_comp_path(listing.show, mine.id), params: { name: "Abe C.", email: "abe@example.com" } }
      .not_to have_enqueued_job(TicketOrderConfirmationJob)
    expect { patch my_show_ticket_comp_path(listing.show, mine.id), params: { name: "Abe Corrected", email: "abe.new@example.com" } }
      .to have_enqueued_job(TicketOrderConfirmationJob).with(mine.id)
    expect(mine.reload).to have_attributes(buyer_name: "Abe Corrected", buyer_email: "abe.new@example.com")

    patch my_show_ticket_comp_path(listing.show, mine.id), params: { name: "", email: "abe.new@example.com" }
    expect(flash[:alert]).to eq("Add the guest's name.")
    expect(mine.reload.buyer_name).to eq("Abe Corrected")

    # The contractor's comp is the contract's too. The organization's own comp and a sale are not.
    patch my_show_ticket_comp_path(listing.show, dans.id), params: { name: "Dan's Plus-One", email_them: "0" }
    expect(dans.reload.buyer_name).to eq("Dan's Plus-One")
    patch my_show_ticket_comp_path(listing.show, houses.id), params: { name: "Mine Now" }
    expect(response).to have_http_status(:not_found)
    delete my_show_ticket_comp_path(listing.show, bought.id)
    expect(response).to have_http_status(:not_found)
    expect(houses.reload.buyer_name).to eq("House Guest")

    # Removing it frees the seats and gives the number back to the contract.
    expect(TicketSalesAccess.comp_allowance(priya, TicketListing.find(listing.id))).to include(left: 0)
    expect { delete my_show_ticket_comp_path(listing.show, mine.id) }.to change { Ticket.where(ticket_listing_id: listing.id, status: Ticket::SOLD_STATUSES).count }.by(-2)
    expect(flash[:notice]).to eq("Removed 2 tickets for Abe Corrected. The seats are free again, and they have been notified by email.")
    expect(TicketSalesAccess.comp_allowance(priya, TicketListing.find(listing.id))).to include(left: 2)
    get my_show_tickets_path(listing.show)
    expect(response.body).not_to include("edit-comp-#{mine.id}")

    # Once the show has started, a comp stays as it is.
    post my_show_ticket_comps_path(listing.show), params: { name: "Late Guest", quantity: "1", tier_id: tier.id }
    late = listing.ticket_orders.find_by!(buyer_name: "Late Guest")
    show.update_columns(date_and_time: 1.hour.ago)
    delete my_show_ticket_comp_path(listing.show, late.id)
    expect(flash[:alert]).to eq("This comp can't be removed any more.")
    patch my_show_ticket_comp_path(listing.show, late.id), params: { name: "Too Late" }
    expect(flash[:alert]).to eq("This comp can't be changed any more.")
    expect(late.reload.buyer_name).to eq("Late Guest")
  end

  it "keeps a comp whose guest has already checked in" do
    listing = open_box_office
    TicketingProfile.for(org).update!(contract_comps_own: true, contract_comps: true, contract_comps_per_show: 3)
    sign_in(priya)
    post my_show_ticket_comps_path(listing.show), params: { name: "Early Bird", quantity: "1", tier_id: listing.ticket_tiers.first.id }
    comp = listing.ticket_orders.find_by!(buyer_name: "Early Bird")
    comp.tickets.first.update_columns(status: "checked_in", checked_in_at: Time.current)

    delete my_show_ticket_comp_path(listing.show, comp.id)
    expect(flash[:alert]).to eq("Early Bird has already checked in, so this comp can't be removed.")
    expect(comp.tickets.first.reload.status).to eq("checked_in")
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
    get my_show_tickets_path(listing.show)
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
    expect(response.body).to include(">Who&#39;s on it<", amend_people_manage_contract_path(contract))

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

    # Someone in the contacts with no account (Tim, 2026-10-18: "search for Athena, see she's not there,
    # create her account, send it to her"): invited to make one, and the invitation carries her profile.
    athena = create(:person, name: "Athena Rae", email: "athena@example.com")
    org.people << athena
    expect { post add_amend_person_manage_contract_path(contract), params: { person_id: athena.id } }
      .to have_enqueued_mail(Manage::TeamMailer, :contract_invite)
    expect(flash[:notice]).to eq("Invited Athena Rae. They're on the contract once they accept.")
    athena_invite = TeamInvitation.find_by(email: "athena@example.com", contract: contract)
    expect(athena_invite.person).to eq(athena)
    expect(contract.contract_people.where(person: athena)).not_to exist
    get amend_people_manage_contract_path(contract)
    expect(response.body).to include("athena@example.com", "Invited, not yet accepted")
    athena_invite.destroy!

    delete remove_amend_person_manage_contract_path(contract), params: { person_id: priya_person.id }
    delete remove_amend_person_manage_contract_path(contract), params: { invitation_id: invitation.id }
    expect(contract.contract_people.reload.map(&:person)).to eq([ sam_person ])
    expect(TeamInvitation.where(contract: contract)).to be_empty

    # Dropped from the contract, Priya has no way to the date.
    sign_in(priya)
    get my_show_path(show)
    expect(response).to redirect_to(my_shows_path)
  end

  it "orders a contract for a phone: money and what to do next before payments, details and terms last (V1.1 plan §4)" do
    sign_in(owner)
    get manage_contract_path(contract)
    doc = Nokogiri::HTML(response.body)
    order_of = ->(title) { doc.css("h2, h3").find { |h| h.text.squish == title }&.ancestors("div")&.find { |d| d["class"].to_s.match?(/max-lg:order-\d+/) }&.[]("class")&.[](/max-lg:order-(\d+)/, 1).to_i }
    expect(order_of.("Financial Summary")).to be < order_of.("Payments")
    expect(order_of.("Payments")).to be < order_of.("Space Bookings")
    expect(order_of.("Space Bookings")).to be < order_of.("Documents")
    expect(order_of.("Documents")).to be < order_of.("Contractor Information")
    expect(doc.css(".max-lg\\:contents").size).to eq(2)
  end
end
