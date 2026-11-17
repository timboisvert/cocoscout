# frozen_string_literal: true

require "rails_helper"

# One show, two organizations, through the pages: the contractor's connect
# steps, the other organization's answer, and what each side then sees of
# the dates and their ticket sales.
RSpec.describe "Contract connections", type: :request do
  let(:password) { "Password123!" }
  # The organization that wrote the contract and sells the tickets.
  let!(:owner) { create(:user, password: password) }
  let!(:owner_person) { create(:person, user: owner) }
  let!(:venue) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  let!(:location) { create(:location, organization: venue, name: "Main room") }
  # The contractor, who runs an organization of their own.
  let!(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Thea Example") }
  let!(:theirs) { create(:organization, :pro, owner: user, name: "The Holly Problem") }
  let!(:contractor) { create(:contractor, organization: venue, person: person) }
  let!(:production) { create(:production, organization: venue, production_type: "third_party", name: "The Holly Problem") }
  let!(:contract) do
    create(:contract, :active, organization: venue, production: production, contractor: contractor,
                               contractor_name: contractor.name, contractor_email: contractor.email)
  end
  let(:night) { 3.weeks.from_now.in_time_zone(venue.time_zone).change(hour: 20, min: 0) }
  let!(:rental) { contract.space_rentals.create!(location: location, starts_at: night, ends_at: night + 2.hours, confirmed: true) }
  let!(:contract_show) { production.shows.create!(date_and_time: night, duration_minutes: 120, location: location, space_rental: rental) }
  let!(:their_production) { create(:production, organization: theirs, name: "The Holly Problem") }
  let!(:their_location) { create(:location, organization: theirs) }

  before do
    create(:organization_role, :manager, user: owner, organization: venue)
    create(:organization_role, :manager, user: user, organization: theirs)
    user.update!(default_person: person)
    owner.update!(default_person: owner_person)
    venue.update!(contract_notification_user_ids: [ owner.id ])
  end

  def sign_in(who)
    post handle_signin_path, params: { email_address: who.email_address, password: password }
  end

  def connected!
    connection = ContractConnections.request!(contract: contract, user: user, organization: theirs, production: their_production)
    ContractConnections.accept!(connection, user: owner, later_contracts: "production")
  end

  # The other organization opens its box office and puts the date on sale.
  def on_sale!
    TicketingProfile.for(venue).update!(enabled: true)
    listing = create(:ticket_listing, organization: venue, production: production, show: contract_show, status: "on_sale")
    listing
  end

  describe "the contractor's steps" do
    before { sign_in(user) }

    it "offers to connect on My Contracts, to someone who runs an organization" do
      get my_contracts_path

      expect(response.body).to include("Connect your organization").and include(my_connect_contract_path(contract))
    end

    it "walks through what it does, the production, and what they'll see" do
      get my_connect_contract_path(contract)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Connect your contract to The Holly Problem")
      # Who the contract is with and what it's for, not "X is your show, and you run it in X".
      expect(response.body).to include("Stars and Garters has a contract with #{contractor.name} to present 1 date of The Holly Problem.")
        .and include("You also run an organization of your own on CocoScout, The Holly Problem.")

      get my_connect_contract_production_path(contract)
      expect(response.body).to include("Where would you like these dates to go?").and include("Same name as the contract").and include("Create a new production for them")

      # Nothing of theirs to weigh: the dates step passes straight through.
      get my_connect_contract_dates_path(contract, organization_id: theirs.id, production: their_production.id)
      expect(response).to redirect_to(my_connect_contract_review_path(contract, organization_id: theirs.id, production: their_production.id))

      get my_connect_contract_review_path(contract, organization_id: theirs.id, production: their_production.id)
      expect(response.body).to include("Send the request").and include("What Stars and Garters will see")
    end

    it "asks about a date of theirs on the same day at another time" do
      their_production.shows.create!(date_and_time: night - 30.minutes, duration_minutes: 120, location: their_location, secondary_name: "Holly at S&G")

      get my_connect_contract_dates_path(contract, organization_id: theirs.id, production: their_production.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("are these the same show?").and include("not sure yet").and include("Keep 7:30 PM as the call time")
    end

    it "understands a date entered with the booking's start time, and one that already has a call time" do
      # The room is booked from 6:00; the show itself is at 8:00.
      rental.update!(starts_at: night - 2.hours, ends_at: night + 2.hours, event_starts_at: night, event_ends_at: night + 90.minutes)
      entered = their_production.shows.create!(date_and_time: night - 2.hours, duration_minutes: 240, location: their_location, secondary_name: "Holly load-in")

      get my_connect_contract_dates_path(contract, organization_id: theirs.id, production: their_production.id)

      expect(response.body).to include("which is exactly when your booking at Stars and Garters begins")
        .and include("The room is booked from 6:00 PM to 10:00 PM")
        .and include("Keep 6:00 PM as the call time")
      # Likely the same show, so that's where the question starts; it's still theirs to change.
      expect(response.body).to match(/name="pair\[#{contract_show.id}\]" value="#{entered.id}" checked/)

      entered.update_columns(call_time: night - 75.minutes, call_time_enabled: true)
      get my_connect_contract_dates_path(contract, organization_id: theirs.id, production: their_production.id)
      expect(response.body).to include("with the cast called for 6:45 PM").and include("Your 6:45 PM call time stays as it is.")
    end

    it "carries the answers about their dates through to the last step and into the request" do
      near = their_production.shows.create!(date_and_time: night - 30.minutes, duration_minutes: 120, location: their_location)
      answers = { organization_id: theirs.id, production: their_production.id, pair: { contract_show.id.to_s => near.id.to_s }, call: { contract_show.id.to_s => "1" } }

      get my_connect_contract_review_path(contract, answers)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 will be treated as the same show")

      post my_connect_contract_path(contract), params: answers
      expect(ContractConnection.last.date_answers).to include("pairs" => { contract_show.id.to_s => near.id }, "calls" => [ contract_show.id.to_s ])
    end

    it "sends the request, and shows it waiting with a way to take it back" do
      expect do
        post my_connect_contract_path(contract), params: { organization_id: theirs.id, production: their_production.id, note: "So my team can see sales." }
      end.to change(ContractConnection, :count).by(1)
      expect(response).to redirect_to(my_contracts_path)

      get my_contracts_path
      expect(response.body).to include("Waiting for Stars and Garters").and include("Withdraw")

      delete my_connect_contract_path(contract)
      expect(ContractConnection.last.status).to eq("withdrawn")
    end

    it "connects a later contract at once when the other organization already agreed to, and says so on every step" do
      connected!
      later = create(:contract, :active, organization: venue, production: production, contractor: contractor,
                                         contractor_name: contractor.name, contractor_email: contractor.email)
      later_night = night + 2.weeks
      later_rental = later.space_rentals.create!(location: location, starts_at: later_night, ends_at: later_night + 2.hours, confirmed: true)
      production.shows.create!(date_and_time: later_night, duration_minutes: 120, location: location, space_rental: later_rental)

      get my_connect_contract_path(later)
      expect(response.body).to include("has already agreed to connect your later contracts to The Holly Problem")

      get my_connect_contract_review_path(later, organization_id: theirs.id, production: their_production.id)
      expect(response.body).to include("as soon as you press Connect")
      expect(response.body).not_to include("Send the request")

      post my_connect_contract_path(later), params: { organization_id: theirs.id, production: their_production.id }
      expect(later.connections.last.status).to eq("connected")
      follow_redirect!
      expect(response.body).to include("Your contract is now connected")
    end

    it "puts the offer away with Not now, leaving a quiet link, and takes it off their organization's home" do
      get manage_path
      expect(response.body).to include("Your show is booked at Stars and Garters")

      patch my_contract_connection_not_now_path(contract)
      expect(contract.reload.connect_offer_dismissed_at).to be_present

      get my_contracts_path
      expect(response.body).to include("Connect to your organization")
      expect(response.body).not_to include("Connect your organization")
      get manage_path
      expect(response.body).not_to include("Your show is booked at Stars and Garters")
    end

    it "asks for a bank only when a contract has something to pay them, and says who pays" do
      get my_contracts_path
      expect(response.body).not_to include("Connect a bank account for your contract payments")

      create(:contract_payment, contract: contract, show: contract_show, direction: "outgoing", amount: 300, description: "Their share")
      get my_contracts_path
      expect(response.body).to include("Connect a bank account for your contract payments")
        .and include("What Stars and Garters pays you under your contract")
    end

    it "offers to start a new production from the contract, on the production wizard's first step" do
      get manage_productions_wizard_path
      follow_redirect! while response.redirect?

      expect(response.body).to include("Is this the show that Stars and Garters has under contract").and include("Start from the contract")
        .and include(my_connect_contract_production_path(contract, organization_id: theirs.id))
    end

    it "shows a contractor with no organization what connecting does, and how to start one" do
      theirs.update!(owner: create(:user))
      OrganizationRole.where(user: user, organization: theirs).destroy_all

      get my_connect_contract_path(contract)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("in an organization of your own").and include("Create your organization")
      expect(response.body).not_to include("Continue")

      get my_connect_contract_production_path(contract)
      expect(response).to redirect_to(my_contracts_path)
    end

    it "is only the contractor's: a stranger with an organization is turned away" do
      stranger = create(:user, password: password)
      create(:person, user: stranger)
      create(:organization, owner: stranger)
      sign_in(stranger)

      get my_connect_contract_path(contract)
      expect(response).to redirect_to(my_contracts_path)
      expect { post my_connect_contract_path(contract), params: { organization_id: theirs.id, production: their_production.id } }
        .not_to change(ContractConnection, :count)
    end
  end

  describe "the other organization's answer" do
    let!(:connection) { ContractConnections.request!(contract: contract, user: user, organization: theirs, production: their_production, note: "So my team can see sales.") }

    before { sign_in(owner) }

    it "shows the request above the contract, with what each side gets and the later-contracts choice" do
      get manage_contract_path(contract)

      expect(response.body).to include("requests to connect this contract").and include("also runs an organization on CocoScout, called The Holly Problem")
        .and include("So my team can see sales.").and include("Later contracts with").and include("Ask us each time")
    end

    it "lets the organization go back to its own images on its ticket page, and to theirs again" do
      post accept_connection_manage_contract_path(contract), params: { later_contracts: "ask" }
      get manage_contract_path(contract)
      expect(response.body).to include("Images on your ticket page").and include("Use our own instead")

      patch connection_images_manage_contract_path(contract), params: { use_own_images: "1" }
      expect(connection.reload.use_own_images).to be(true)
      follow_redirect!
      expect(response.body).to include("using your own images and description")
    end

    it "says who the contractor is on CocoScout on the contractor's page, once connected" do
      post accept_connection_manage_contract_path(contract), params: { later_contracts: "ask" }
      get manage_contractor_path(contractor)

      expect(response.body).to include("On CocoScout as").and include("The Holly Problem")
    end

    it "accepts: the dates go into their production, and the contract says who they are" do
      post accept_connection_manage_contract_path(contract), params: { later_contracts: "all" }

      expect(connection.reload).to have_attributes(status: "connected", later_contracts: "all")
      expect(their_production.shows.where(linked_show: contract_show)).to exist
      get manage_contract_path(contract)
      expect(response.body).to include("On CocoScout as The Holly Problem").and include("Who sees ticket sales")
    end

    it "declines with a note" do
      post decline_connection_manage_contract_path(contract), params: { answer_note: "After the run." }

      expect(connection.reload).to have_attributes(status: "declined", answer_note: "After the run.")
    end

    it "unlinks later, and their dates stay as their own" do
      ContractConnections.accept!(connection, user: owner)
      post unlink_connection_manage_contract_path(contract)

      expect(connection.reload.status).to eq("unlinked")
      expect(their_production.shows.first).to have_attributes(linked_show_id: nil)
    end

    it "lets the organization notify the contractor that a contract can be connected, once, before anything connects it" do
      connection.update!(status: "withdrawn")
      connection.destroy!
      get manage_contract_path(contract)
      expect(response.body).to include("run this show on CocoScout too?").and include("Notify #{contractor.name}")

      expect { post tell_connection_manage_contract_path(contract) }.to change(user.notifications, :count).by(1)
      follow_redirect!
      expect(response.body).to include("was notified on")
      expect(response.body).not_to include("Notify #{contractor.name}")
    end

    it "never reaches another organization's contract" do
      other = create(:organization, :pro)
      other_production = create(:production, organization: other, production_type: "third_party")
      theirs_elsewhere = create(:contract, :active, organization: other, production: other_production)

      post accept_connection_manage_contract_path(theirs_elsewhere)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "what the contractor's organization then sees" do
    let!(:connection) { connected! }
    let(:followed) { their_production.shows.find_by!(linked_show: contract_show) }

    it "lists the connection, with who sees the sales and Unlink" do
      sign_in(user)
      get manage_connections_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stars and Garters").and include("1 of 1 in your production").and include("Who in The Holly Problem sees")
    end

    it "saves who sees the sales, and unlinks from its own side" do
      sign_in(user)
      patch manage_connection_path(connection), params: { connection: { cast_sales: "nothing", team_viewer_sales: "nothing" } }
      expect(connection.reload).to have_attributes(cast_sales: "nothing", team_viewer_sales: "nothing")

      # Unlink is a page of its own: what it ends, the smaller options, and the coming dates.
      get manage_unlinking_connection_path(connection)
      expect(response.body).to include("You might not need to unlink").and include("What should happen to the 1 date still to come?")

      post manage_unlink_connection_path(connection), params: { dates: "keep" }
      expect(connection.reload.status).to eq("unlinked")
      expect(their_production.shows.count).to eq(1)

      get manage_connections_path
      expect(response.body).to include("1 coming date from this contract is still in The Holly Problem as your own")
      get manage_show_path(their_production, their_production.shows.first)
      expect(response.body).to include("That connection has ended")

      post manage_connection_remove_dates_path(connection)
      expect(their_production.shows.count).to eq(0)
    end

    it "removes the coming dates when unlinking, if asked to" do
      sign_in(user)
      post manage_unlink_connection_path(connection), params: { dates: "remove" }

      expect(their_production.shows.count).to eq(0)
      expect(flash[:notice]).to include("The coming dates were removed")
    end

    it "shows the date as booked there, at their venue, with nothing to move or delete" do
      sign_in(user)
      get manage_show_path(their_production, followed)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Booked at Stars and Garters").and include("Main room")
      expect(response.body).not_to include("Cancel Show")
      expect(response.body).not_to include("Transfer Show")

      get manage_edit_show_path(their_production, followed)
      expect(response.body).to include("This date is booked at Stars and Garters")
    end

    it "shows the other organization's ticket numbers, read-only, on the date, the production and its sales page" do
      on_sale!
      sign_in(user)

      get manage_show_path(their_production, followed)
      expect(response.body).to include("Tickets at Stars and Garters").and include("See ticket sales")

      get manage_production_sales_path(their_production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("is selling at Stars and Garters").and include("stay with Stars and Garters")

      get manage_production_path(their_production)
      expect(response.body).to include("Sold by Stars and Garters")
    end

    it "shows the people who manage it what the contract pays for a date, and never the production team" do
      on_sale!
      create(:contract_payment, contract: contract, show: contract_show, direction: "outgoing", amount: 412.50,
                                due_date: contract_show.date_and_time.to_date + 3.days, description: "Their share")
      sign_in(user)

      get manage_show_path(their_production, followed)
      expect(response.body).to include("data-followed-contract-box").and include("You get").and include("Payments go to #{contractor.name}.")

      get manage_production_sales_path(their_production)
      expect(response.body).to include("What the contract pays").and include("$412.50")

      # A production team manager sees the numbers their organization chose, not the money.
      teammate = create(:user, password: password)
      create(:person, user: teammate)
      create(:organization_role, user: teammate, organization: theirs, company_role: "member")
      ProductionPermission.create!(user: teammate, production: their_production, role: "manager")
      get signout_path
      sign_in(teammate)
      post set_organization_path(id: theirs.id)
      get manage_production_sales_path(their_production)
      expect(response).to have_http_status(:ok), "went to #{response.location}"
      expect(response.body).not_to include("What the contract pays")
      get manage_show_path(their_production, followed)
      expect(response.body).not_to include("data-followed-contract-box")
    end

    it "lets another manager of the contractor's organization give comps from what the date has left" do
      listing = on_sale!
      tier = listing.ticket_tiers.first || listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 40)
      colleague = create(:user, password: password)
      create(:person, user: colleague)
      create(:organization_role, :manager, user: colleague, organization: theirs)
      expect(TicketSalesAccess.comp_allowance(colleague, listing)).to include(contract: true)

      sign_in(colleague)
      post set_organization_path(id: theirs.id)
      expect do
        post manage_production_sale_comps_path(their_production, listing), params: { name: "A Friend", quantity: "1", tier_id: tier.id }
      end.to change { listing.tickets.count }.by(1)

      # Not once the seller stops sharing.
      contract.update!(shares_ticket_sales: false)
      expect(TicketSalesAccess.comp_allowance(colleague, listing)).to be_nil
    end

    it "shows buyers the show's own description on the seller's ticket page, and the seller's again once it chooses its own" do
      listing = on_sale!
      listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 40) if listing.ticket_tiers.empty?
      production.update!(description: "The venue wrote this.")
      their_production.update!(description: "The show wrote this itself.")
      slug = TicketingProfile.for(venue).slug

      get tickets_event_path(org: slug, event: production.ticket_page_key)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("The show wrote this itself.")
      expect(response.body).not_to include("The venue wrote this.")

      connection.update!(use_own_images: true)
      get tickets_event_path(org: slug, event: production.ticket_page_key)
      expect(response.body).to include("The venue wrote this.")
    end

    it "shows everyone on the contract what the contractor sees, not only the contractor" do
      on_sale!
      create(:contract_payment, contract: contract, show: contract_show, direction: "outgoing", amount: 250, description: "Their share")
      colleague = create(:user, password: password)
      colleague_person = create(:person, user: colleague, name: "Robin On The Contract")
      ContractPerson.create!(contract: contract, person: colleague_person)
      # In The Holly Problem only as a production team viewer, whose own level is the numbers.
      create(:organization_role, user: colleague, organization: theirs, company_role: "member")
      ProductionPermission.create!(user: colleague, production: their_production, role: "viewer")
      expect(LinkedTicketSales.level_for(colleague, followed)).to eq(:full)

      sign_in(colleague)
      post set_organization_path(id: theirs.id)
      get manage_production_sales_path(their_production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("What the contract pays").and include("$250.00")
    end

    it "says where a coming date is booked on the production page, and doesn't ask where its tickets are sold" do
      sign_in(user)
      get manage_production_path(their_production)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Booked at Stars and Garters")
      expect(response.body).not_to include("Where people get tickets isn&#39;t set")
    end

    it "puts them first on Ticketing, with no push to open a box office" do
      on_sale!
      sign_in(user)
      get manage_ticketing_path

      expect(response.body).to include("Sold by Stars and Garters").and include("Your own box office is closed")
      expect(response.body).not_to include("Your box office isn&#39;t open yet")
    end

    it "stops every layer when the other organization stops sharing" do
      on_sale!
      contract.update!(shares_ticket_sales: false)
      sign_in(user)

      get manage_show_path(their_production, followed)
      expect(response.body).not_to include("Tickets at Stars and Garters")
      # Never on to their own Ticketing, to set up a box office for dates they don't sell.
      get manage_production_sales_path(their_production)
      expect(response).to redirect_to(manage_production_path(their_production))
      expect(flash[:notice]).to include("isn't sharing its ticket sales")
    end

    it "shows a cast member the count and the link, and nothing more" do
      on_sale!
      performer = create(:user, password: password)
      performer_person = create(:person, user: performer)
      theirs.people << performer_person unless theirs.people.include?(performer_person)
      their_production.effective_talent_pool.talent_pool_memberships.create!(member: performer_person)
      role = create(:role, production: their_production)
      followed.show_person_role_assignments.create!(role: role, assignable: performer_person)
      followed.update_columns(casting_finalized_at: Time.current)
      sign_in(performer)

      get my_show_path(followed)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sold by Stars and Garters").and include("Tickets sold")
      expect(response.body).not_to include("View ticket sales")

      connection.update!(cast_sales: "nothing")
      get my_show_path(followed)
      expect(response.body).not_to include("Sold by Stars and Garters")
    end

    it "keeps the Connections page and their numbers from anyone outside" do
      outsider = create(:user, password: password)
      create(:person, user: outsider)
      elsewhere = create(:organization, :pro, owner: outsider)
      create(:organization_role, :manager, user: outsider, organization: elsewhere)
      sign_in(outsider)

      patch manage_connection_path(connection), params: { connection: { cast_sales: "nothing" } }
      expect(response).to have_http_status(:not_found)
      expect(connection.reload.cast_sales).to eq("production_cast")
    end
  end
end
