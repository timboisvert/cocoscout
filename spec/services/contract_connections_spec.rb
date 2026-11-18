# frozen_string_literal: true

require "rails_helper"

# One show, two organizations: a contract connected to the contractor's own
# organization. The request and its answers, the dates that arrive and
# follow, and what happens to dates that were already there.
RSpec.describe ContractConnections do
  # The organization that wrote the contract.
  let!(:owner) { create(:user) }
  let!(:owner_person) { create(:person, user: owner) }
  let!(:venue) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  let!(:location) { create(:location, organization: venue, name: "Main room") }
  # The contractor, who also runs an organization of their own.
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user) }
  let!(:theirs) { create(:organization, :pro, owner: user, name: "The Holly Problem") }
  let!(:contractor) { create(:contractor, organization: venue, person: person) }
  let!(:production) { create(:production, organization: venue, production_type: "third_party", name: "The Holly Problem") }
  let!(:contract) do
    create(:contract, :active, organization: venue, production: production, contractor: contractor,
                               contractor_name: contractor.name, contractor_email: contractor.email)
  end
  let(:first_night) { 3.weeks.from_now.in_time_zone(venue.time_zone).change(hour: 20, min: 0) }
  let(:second_night) { first_night + 1.day }
  let!(:first_show) { booked!(first_night) }
  let!(:second_show) { booked!(second_night) }
  let!(:their_production) { create(:production, organization: theirs, name: "The Holly Problem") }
  let!(:their_location) { create(:location, organization: theirs) }

  before { venue.update!(contract_notification_user_ids: [ owner.id ]) }

  def booked!(starts_at)
    rental = contract.space_rentals.create!(location: location, starts_at: starts_at, ends_at: starts_at + 2.hours, confirmed: true)
    production.shows.create!(date_and_time: starts_at, duration_minutes: 120, location: location, space_rental: rental)
  end

  # The other organization moves the first night, the way Change dates does.
  def move_first_night!(to)
    ContractDateChanges.move!(contract: contract, rental: first_show.space_rental, starts_at: to, ends_at: to + 2.hours)
  end

  def own_show!(at, **attributes)
    their_production.shows.create!({ date_and_time: at, duration_minutes: 120, location: their_location, event_type: "show" }.merge(attributes))
  end

  def request!(**options)
    described_class.request!(**{ contract: contract, user: user, organization: theirs, production: their_production }.merge(options))
  end

  def connect!(**options)
    described_class.accept!(request!(**options), user: owner, later_contracts: "production")
  end

  describe "who can request" do
    it "is the contractor, when they run an organization of their own" do
      expect(described_class.can_request?(user, contract)).to be(true)
      expect(described_class.organizations_for(user, contract)).to contain_exactly(theirs)
    end

    it "isn't someone who runs no organization, nor a stranger who does" do
      theirs.update!(owner: create(:user))
      expect(described_class.can_request?(user, contract)).to be(false)

      stranger = create(:user)
      create(:person, user: stranger)
      create(:organization, owner: stranger)
      expect(described_class.can_request?(stranger, contract)).to be(false)
    end

    it "never offers the organization the contract is with" do
      contractor.update!(person: owner_person)
      expect(described_class.organizations_for(owner, contract)).to be_empty
    end
  end

  describe ".request!" do
    it "waits for the other organization, which is notified" do
      connection = nil
      expect { connection = request!(note: "Connecting so my team can see sales.") }.to change(owner.notifications, :count).by(1)

      expect(connection).to have_attributes(status: "requested", organization: venue, linked_organization: theirs, linked_production: their_production)
      expect(owner.notifications.last.title).to include("requests to connect The Holly Problem")
      expect(their_production.shows).to be_empty
    end

    it "allows one live connection per contract" do
      request!
      expect { request! }.to raise_error(described_class::NotAllowed)
    end

    it "can be taken back, with the unopened notification about it" do
      connection = request!
      described_class.withdraw!(connection, user: user)

      expect(connection.reload.status).to eq("withdrawn")
      expect(owner.notifications.where(subject: connection)).to be_empty
      expect(described_class.can_request?(user, contract)).to be(true)
    end
  end

  describe ".decline!" do
    it "says no with a note, and changes nothing of theirs" do
      connection = request!
      expect { described_class.decline!(connection, user: owner, note: "Mid-season, let's talk after.") }.to change(user.notifications, :count).by(1)

      expect(connection.reload).to have_attributes(status: "declined", answer_note: "Mid-season, let's talk after.")
      expect(their_production.shows).to be_empty
    end
  end

  describe ".accept!" do
    it "brings a rehearsal on the contract in as a rehearsal, never compared with their shows" do
      # They rehearse in the room too (Tim, 2026-11-18). It arrived as a show.
      first_show.update_columns(event_type: "rehearsal")
      own = own_show!(first_night + 1.hour)

      comparison = LinkedDates.compare(contract, their_production)
      expect(comparison.added).to include(first_show)
      expect(comparison.questions.map(&:first)).not_to include(first_show)

      connect!
      arrived = their_production.shows.find_by!(linked_show: first_show)
      expect(arrived).to have_attributes(event_type: "rehearsal", casting_enabled: false)
      expect(their_production.shows.find_by!(linked_show: second_show)).to have_attributes(event_type: "show", casting_enabled: true)
      expect(own.reload.linked_show_id).to be_nil
    end

    it "brings a show in with casting off when people aren't cast in their production" do
      # A date that arrives follows the production it arrives in (Tim,
      # 2026-11-18): "We don't cast people in this production".
      their_production.update!(casts_people: false)

      connect!
      expect(their_production.shows.where.not(linked_show_id: nil).pluck(:casting_enabled)).to eq([ false, false ])
    end

    it "puts every date on the contract into their production, following it" do
      connection = nil
      expect { connection = connect! }.to change(user.notifications, :count).by(1)

      expect(connection.reload).to have_attributes(status: "connected", later_contracts: "production", answered_by: owner)
      arrived = their_production.shows.order(:date_and_time)
      expect(arrived.map(&:linked_show)).to eq([ first_show, second_show ])
      expect(arrived.map(&:date_and_time)).to eq([ first_night, second_night ])
      expect(arrived.first).to have_attributes(location_id: nil, is_online: false)
      expect(arrived.first.venue_location).to eq(location)
      expect(arrived.first.followed_organization).to eq(venue)
    end

    it "makes the production from the contract when they asked for a new one" do
      connection = described_class.accept!(request!(production: nil, new_production_name: "Holly at S&G"), user: owner)

      expect(connection.linked_production).to have_attributes(name: "Holly at S&G", organization: theirs)
      expect(connection.linked_production.shows.count).to eq(2)
    end

    it "lets every date arrive on the free plan, past its six a month, and still counts them" do
      free = create(:organization, owner: user, name: "Free Holly")
      free_production = create(:production, organization: free)
      6.times { |i| booked!(first_night + (i + 2).days) }

      described_class.accept!(request!(organization: free, production: free_production), user: owner)

      expect(free_production.shows.count).to eq(8)
      own = free_production.shows.new(date_and_time: first_night + 12.hours, duration_minutes: 60, is_online: true)
      expect(own).not_to be_valid
      expect(own.errors.full_messages.to_sentence).to include("free plan limit")
    end
  end

  describe "dates that were already there" do
    it "treats one they said is the same show as the contract's, keeping its cast and its old time as the call" do
      own = own_show!(first_night - 30.minutes, secondary_name: "Holly at S&G")
      role = create(:role, production: their_production)
      assignment = own.show_person_role_assignments.create!(role: role, assignable: create(:person))
      answers = LinkedDates.answers_from(contract, their_production, pair: { first_show.id.to_s => own.id.to_s }, call: { first_show.id.to_s => "1" })

      connect!(date_answers: answers)

      expect(own.reload).to have_attributes(linked_show: first_show, date_and_time: first_night, location_id: nil,
                                            call_time: first_night - 30.minutes, call_time_enabled: true)
      expect(own.show_person_role_assignments).to contain_exactly(assignment)
      expect(their_production.shows.count).to eq(2)
    end

    it "offers the same day and time as a match, and the same day at another time as a question" do
      exact = own_show!(first_night)
      near = own_show!(second_night - 30.minutes)
      later = own_show!(second_night + 10.days)
      own_show!(first_night - 2.days, event_type: "rehearsal")

      comparison = LinkedDates.compare(contract, their_production)

      expect(comparison.matches).to eq([ [ first_show, exact ] ])
      expect(comparison.questions).to eq([ [ second_show, [ near ] ] ])
      expect(comparison.added).to be_empty
      expect(comparison.theirs_only).to eq([ later ])
    end

    it "never touches a call time the date already had" do
      own = own_show!(first_night - 30.minutes)
      own.update!(call_time: first_night - 90.minutes, call_time_enabled: true)
      answers = LinkedDates.answers_from(contract, their_production, pair: { first_show.id.to_s => own.id.to_s }, call: { first_show.id.to_s => "1" })

      connect!(date_answers: answers)

      expect(own.reload).to have_attributes(linked_show: first_show, date_and_time: first_night, call_time: first_night - 90.minutes)
    end

    it "asks about a date that starts when the booking does, or late the same night" do
      first_show.space_rental.update!(starts_at: first_night - 2.hours, event_starts_at: first_night, event_ends_at: first_night + 2.hours)
      load_in = own_show!(first_night - 2.hours)
      late = own_show!(second_night + 3.hours)

      comparison = LinkedDates.compare(contract, their_production)

      expect(comparison.questions).to eq([ [ first_show, [ load_in ] ], [ second_show, [ late ] ] ])
      expect(comparison.reason_for(first_show, load_in)).to eq(:booking_start)
      expect(comparison.likely_same(first_show, [ load_in ])).to eq(load_in)
      expect(comparison.likely_same(second_show, [ late ])).to be_nil
    end

    it "leaves a date alone unless they said so: an unanswered question keeps both" do
      near = own_show!(first_night - 30.minutes)
      connection = connect!(date_answers: LinkedDates.answers_from(contract, their_production, pair: {}))

      expect(near.reload).to have_attributes(linked_show_id: nil, date_and_time: first_night - 30.minutes, location: their_location)
      expect(their_production.shows.count).to eq(3)
      expect(LinkedDates.open_questions(connection)).to eq([ [ first_show, near ] ])
    end

    it "answers an open question later: the same show after all" do
      near = own_show!(first_night - 30.minutes)
      connection = connect!(date_answers: LinkedDates.answers_from(contract, their_production, pair: {}))

      LinkedDates.resolve!(connection, contract_show_id: first_show.id, show_id: near.id, same: true)

      expect(near.reload).to have_attributes(linked_show: first_show, date_and_time: first_night)
      expect(their_production.shows.count).to eq(2)
      expect(LinkedDates.open_questions(connection.reload)).to be_empty
    end
  end

  describe "keeping in step" do
    let!(:connection) { connect! }
    let(:arrived) { their_production.shows.find_by!(linked_show: first_show) }

    it "follows a move" do
      rental = first_show.space_rental
      ContractDateChanges.move!(contract: contract, rental: rental, starts_at: first_night - 1.hour, ends_at: first_night + 1.hour)

      expect(arrived.reload.date_and_time).to eq(first_night - 1.hour)
    end

    it "follows a cancellation" do
      first_show.update!(canceled: true)
      expect(arrived.reload.canceled).to be(true)
    end

    it "takes a date added to the contract" do
      added = booked!(first_night + 7.days)
      expect(their_production.shows.find_by(linked_show: added)).to be_present
    end

    it "keeps their date, canceled, when the contract's is removed" do
      arrived
      ContractDateChanges.remove!(contract: contract, rental: first_show.space_rental)

      kept = arrived.reload
      expect(kept).to have_attributes(linked_show_id: nil, canceled: true)
      expect(kept.location).to have_attributes(organization: theirs, name: "Main room")
    end

    it "can't be moved, canceled or deleted from their side" do
      expect(arrived.update(date_and_time: first_night + 1.hour)).to be(false)
      expect(arrived.errors.full_messages.to_sentence).to include("booked at Stars and Garters")
      expect(arrived.reload.update(canceled: true)).to be(false)
      expect(arrived.reload.destroy).to be(false)
      expect(arrived.reload.update(notes: "Load in at 5")).to be(true)
    end

    it "records their own change to notify the cast, apart from the other side's" do
      role = create(:role, production: their_production)
      arrived.show_person_role_assignments.create!(role: role, assignable: create(:person))
      arrived.update_columns(casting_finalized_at: Time.current)

      expect { move_first_night!(first_night + 30.minutes) }
        .to change { ShowChange.where(organization: theirs, show: arrived).count }.by(1)
      change = ShowChange.where(organization: theirs).last
      expect(change.changed_by_user).to be_nil
      expect(ShowChange.where(batch: change.batch).where.not(organization: theirs)).to be_empty
    end
  end

  describe ".unlink!" do
    it "leaves the dates as their own, in their own record of the venue, and stops following" do
      connection = connect!
      expect { described_class.unlink!(connection, user: owner) }.to change(user.notifications, :count).by(1)

      expect(connection.reload.status).to eq("unlinked")
      kept = their_production.shows.order(:date_and_time)
      expect(kept.map(&:linked_show_id)).to eq([ nil, nil ])
      expect(kept.first.location).to have_attributes(organization: theirs, name: "Main room")
      move_first_night!(first_night + 1.hour)
      expect(kept.first.reload.date_and_time).to eq(first_night)
    end

    it "marks the dates it leaves, and can remove the coming ones nobody is on" do
      connection = connect!
      followed = their_production.shows.find_by!(linked_show: first_show)
      role = create(:role, production: their_production)
      followed.show_person_role_assignments.create!(role: role, assignable: create(:person))

      described_class.unlink!(connection, user: user, remove_coming: true)

      # The one with someone cast stays, marked; the other is gone.
      expect(followed.reload).to have_attributes(linked_show_id: nil, released_connection_id: connection.id)
      expect(their_production.shows.count).to eq(1)
      expect(LinkedDates.released_coming(connection)).to contain_exactly(followed)
    end

    it "keeps every date when the other organization unlinks, and lets the contractor's side remove the coming ones later" do
      connection = connect!
      described_class.unlink!(connection, user: owner, remove_coming: true)
      expect(their_production.shows.count).to eq(2)

      expect(LinkedDates.remove_released!(connection)).to eq([ 2, 0 ])
      expect(their_production.shows.count).to eq(0)
    end

    it "takes the mark off again when the contract is connected again" do
      first = connect!
      described_class.unlink!(first, user: user)
      kept = their_production.shows.find_by!(date_and_time: first_show.date_and_time)
      again = described_class.request!(contract: contract, user: user, organization: theirs, production: their_production,
                                       date_answers: LinkedDates.answers_from(contract, their_production, pair: { first_show.id.to_s => kept.id.to_s }, call: {}, join: {}))
      described_class.accept!(again, user: owner)

      expect(kept.reload).to have_attributes(linked_show_id: first_show.id, released_connection_id: nil)
    end

    it "notifies the other organization when the contractor's side ends it" do
      connection = connect!
      expect { described_class.unlink!(connection, user: user) }.to change(owner.notifications, :count).by(1)
      expect(owner.notifications.last.title).to include("unlinked the contract")
    end
  end

  describe "a later contract" do
    # Another contract with the same contractor, after the first is connected.
    def later_contract(for_production: production)
      later = create(:contract, :active, organization: venue, production: for_production, contractor: contractor,
                                         contractor_name: contractor.name, contractor_email: contractor.email)
      night = first_night + 2.weeks
      rental = later.space_rentals.create!(location: location, starts_at: night, ends_at: night + 2.hours, confirmed: true)
      for_production.shows.create!(date_and_time: night, duration_minutes: 120, location: location, space_rental: rental)
      later
    end

    def request_later!(later)
      described_class.request!(contract: later, user: user, organization: theirs, production: their_production)
    end

    it "connects without waiting for approval when they chose to connect later contracts for the production, and they're notified" do
      connect!
      later = later_contract

      connection = nil
      expect { connection = request_later!(later) }.to change(owner.notifications, :count).by(1)
      expect(connection).to have_attributes(status: "connected", later_contracts: "production", answered_by: owner)
      expect(owner.notifications.last.title).to include("connected the contract")
      expect(user.notifications.where(kind: "contract_connection_accepted").count).to eq(1)
      expect(LinkedDates.following_for(connection).count).to eq(1)
    end

    it "still waits when the later contract is for another production of theirs" do
      connect!
      other = create(:production, organization: venue, production_type: "third_party", name: "Another Show")

      expect(request_later!(later_contract(for_production: other)).status).to eq("requested")
    end

    it "covers any production when they chose every later contract" do
      connect!.update!(later_contracts: "all")
      other = create(:production, organization: venue, production_type: "third_party", name: "Another Show")

      expect(request_later!(later_contract(for_production: other)).status).to eq("connected")
    end

    it "waits when they chose to be asked each time, when the first was unlinked, and for another organization of the contractor's" do
      first = connect!
      later = later_contract
      first.update!(later_contracts: "ask")
      expect(described_class.standing_yes(later, organization: theirs)).to be_nil

      first.update!(later_contracts: "all")
      elsewhere = create(:organization, :pro, owner: user, name: "Another Company")
      expect(described_class.standing_yes(later, organization: elsewhere)).to be_nil
      expect(described_class.standing_yes(later, organization: theirs)).to eq(first)

      described_class.unlink!(first, user: owner)
      expect(described_class.standing_yes(later, organization: theirs)).to be_nil
    end
  end

  describe "the offer" do
    # The let! records are made before the contract has dates, so nothing
    # has been offered yet: this is the moment it first becomes true.
    before { contract.update_columns(connect_offered_at: nil) }

    it "notifies the contractor once, when they run an organization and the contract has dates ahead" do
      expect { described_class.offer!(contract) }.to change(user.notifications, :count).by(1)
      expect(user.notifications.last.title).to eq("You can connect your Stars and Garters contract to The Holly Problem")
      expect { described_class.offer!(contract) }.not_to change(user.notifications, :count)
    end

    it "is made when someone comes to run an organization, and when a contract goes live" do
      theirs.update!(owner: create(:user))
      expect(described_class.offer!(contract)).to be(false)

      expect { create(:organization, owner: user, name: "A New Company") }.to change(user.notifications, :count).by(1)
      expect(user.notifications.last.title).to include("You can connect your Stars and Garters contract to A New Company")
    end

    it "says nothing for a contract whose dates are over, one already connected, or a contractor with no organization" do
      first_show.update_columns(date_and_time: 2.days.ago)
      second_show.update_columns(date_and_time: 1.day.ago)
      expect(described_class.offer!(contract)).to be(false)

      first_show.update_columns(date_and_time: first_night)
      request!
      expect(described_class.offer!(contract)).to be(false)
    end

    it "is put away with Not now, and then is no longer a line on their organization's home" do
      expect(described_class.offers_for(user, theirs)).to contain_exactly(contract)
      described_class.not_now!(contract, user: user)
      expect(described_class.offers_for(user, theirs)).to be_empty
      expect { described_class.not_now!(contract, user: owner) }.to raise_error(described_class::NotAllowed)
    end
  end

  describe ".tell!" do
    it "lets the organization notify the contractor once that the contract can be connected" do
      expect(described_class.can_tell?(contract)).to be(true)
      expect { described_class.tell!(contract, user: owner) }.to change(user.notifications, :count).by(1)
      expect(user.notifications.last.title).to eq("Stars and Garters invites you to link your production to their contract")
      expect(contract.reload).to have_attributes(connect_told_by_id: owner.id)
      expect(described_class.can_tell?(contract)).to be(false)
      expect { described_class.tell!(contract, user: owner) }.not_to change(user.notifications, :count)
    end

    it "isn't offered for a contractor who can't sign in, or once a connection has been requested" do
      request!
      expect(described_class.can_tell?(contract)).to be(false)
    end
  end

  describe "whose images the ticket page shows (LinkedArt)" do
    # A fresh file each time: an attached one has been read to its end.
    def png = { io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")), filename: "wide.png", content_type: "image/png" }

    it "puts the contractor's production's wide image and description ahead of the seller's own, while connected" do
      production.update!(description: "The venue's words.")
      their_production.update!(description: "The show's own words.")
      their_production.wide_image.attach(**png)
      listing = create(:ticket_listing, organization: venue, production: production, show: first_show)
      expect(first_show.ticket_page_image).to be_nil
      expect(listing.effective_description.to_plain_text).to eq("The venue's words.")

      connection = connect!
      image = Show.find(first_show.id).ticket_page_image
      expect(image).to have_attributes(owner: :partner, kind: :wide, from: "The Holly Problem")
      expect(TicketListing.find(listing.id).effective_description.to_plain_text).to eq("The show's own words.")

      # The seller keeps its own, and it all goes back when the connection ends.
      connection.update!(use_own_images: true)
      expect(Show.find(first_show.id).ticket_page_image).to be_nil
      connection.update!(use_own_images: false)
      described_class.unlink!(connection, user: owner)
      expect(Show.find(first_show.id).ticket_page_image).to be_nil
      expect(TicketListing.find(listing.id).effective_description.to_plain_text).to eq("The venue's words.")
    end

    it "leaves a date's own image first" do
      their_production.wide_image.attach(**png)
      first_show.wide_image.attach(**png)
      connect!

      expect(Show.find(first_show.id).ticket_page_image).to have_attributes(owner: :show)
    end
  end

  describe ".choose_later_contracts!" do
    it "is one answer for the contractor: asking each time on one contract takes back the yes given on another" do
      first = connect!
      first.update!(later_contracts: "all")
      later = create(:contract, :active, organization: venue, production: production, contractor: contractor,
                                         contractor_name: contractor.name, contractor_email: contractor.email)
      second = described_class.request!(contract: later, user: user, organization: theirs, production: their_production)
      expect(second.status).to eq("connected")

      described_class.choose_later_contracts!(second, "ask")
      expect(first.reload.later_contracts).to eq("ask")

      described_class.choose_later_contracts!(second, "all")
      expect(first.reload.later_contracts).to eq("all")

      # Narrowing one to its production narrows the other from "every one" too.
      described_class.choose_later_contracts!(second, "production")
      expect(first.reload.later_contracts).to eq("production")
    end
  end

  describe ".sweep!" do
    it "reminds the other organization once, after three days without an answer" do
      connection = request!
      expect { described_class.sweep!(now: 2.days.from_now) }.not_to change(owner.notifications, :count)
      expect { described_class.sweep!(now: 4.days.from_now) }.to change(owner.notifications, :count).by(1)
      expect(owner.notifications.last.title).to include("still waiting")
      expect { described_class.sweep!(now: 8.days.from_now) }.not_to change(owner.notifications, :count)
      expect(connection.reload.reminded_at).to be_present
    end

    it "says nothing about a request that was answered" do
      connect!
      expect { described_class.sweep!(now: 4.days.from_now) }.not_to change(owner.notifications, :count)
    end
  end
end
