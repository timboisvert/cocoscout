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

      expect(response.body).to include("requests to connect this contract to The Holly Problem")
        .and include("So my team can see sales.").and include("Later contracts with").and include("Ask us each time")
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

      post manage_unlink_connection_path(connection)
      expect(connection.reload.status).to eq("unlinked")
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
