# frozen_string_literal: true

require "rails_helper"

# Every location has a room and every show with a location sits in one
# (1.4). A location's only room is never named (Tim, 2026-11-18): "Main
# room" alone says nothing, so a one-room location reads as the location,
# the way it did before rooms were on everything. A room is named where the
# location has two or more.
RSpec.describe "Naming a room" do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:hall) { create(:location, organization: org, name: "Riverside Hall") }
  let(:show) { create(:show, production: production, location: hall, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }

  it "names no room at a location with one, and the room at a location with several" do
    only_room = hall.location_spaces.sole
    expect(show.location_space).to eq(only_room)
    expect(hall.several_rooms?).to be(false)
    expect(only_room.worth_naming?).to be(false)
    expect(only_room.place_name).to eq("Riverside Hall")
    expect(show.named_room).to be_nil
    expect(show.room_name).to be_nil
    expect(show.place_name).to eq("Riverside Hall")

    studio = hall.location_spaces.create!(name: "Studio B")
    show.reload
    expect(hall.reload.several_rooms?).to be(true)
    expect(show.room_name).to eq("Main room")
    expect(show.place_name).to eq("Main room")
    expect(studio.place_name).to eq("Riverside Hall · Studio B")
  end

  it "names no room for a show with no location, or online" do
    nowhere = create(:show, production: production, location: nil, is_online: true, online_location_info: "A link")
    expect(nowhere.named_room).to be_nil
    expect(nowhere.place_name).to be_nil
  end

  it "says where a show is to buyers, in emails, and on the ticket without a lone room" do
    helper = Class.new { include TicketingHelper }.new
    expect(helper.public_place_name(show)).to eq("Riverside Hall")
    expect(Ticketing::WhenWhere.for(show)).to include(venue: "Riverside Hall", room: nil)

    hall.location_spaces.create!(name: "Studio B")
    show.reload
    expect(helper.public_place_name(show)).to eq("Riverside Hall · Main room")
    expect(Ticketing::WhenWhere.for(show)).to include(venue: "Riverside Hall", room: "Main room")
  end

  it "offers the Google Calendar a color only for rooms worth naming" do
    hall
    theater = create(:location, organization: org, name: "Clark Street")
    mainstage = theater.location_spaces.create!(name: "Mainstage")

    expect(org.calendar_rooms.map(&:name)).to eq([ "Main room", "Mainstage" ])
    expect(org.calendar_rooms.map(&:location)).to all(eq(theater))
    expect(org.calendar_rooms).to include(mainstage)
  end

  describe "a buyer who was told no room" do
    let(:listing) { create(:ticket_listing, organization: org, production: production, show: show) }
    let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

    def bought(name)
      order = create(:ticket_order, ticket_listing: listing, status: "paid", paid_at: Time.current, money_path: "cocoscout",
                                    expires_at: nil, buyer_name: name, buyer_email: "#{name.parameterize}@example.com")
      create(:ticket, ticket_order: order, ticket_tier: general)
      order
    end

    # What 1.4's first migration does to production: a show that had no room
    # gets its location's, long after people bought.
    it "is not asked about when the show is given its location's room" do
      TicketingProfile.for(org).update!(enabled: true)
      dana = bought("Dana Scully")
      dana.update_columns(told_location_space_id: nil)

      expect(show.location_space_id).to be_present
      expect(TicketShowChange.orders(listing)).to be_empty
      expect(TicketShowChange.pending?(listing)).to be(false)

      # A real move is still a move: another location, or another room for
      # someone who was told a room.
      fox = bought("Fox Mulder")
      studio = hall.location_spaces.create!(name: "Studio B")
      show.update!(location_space: studio)
      expect(TicketShowChange.orders(listing)).to contain_exactly(fox)
      expect(TicketShowChange.variables(fox)).to include(what_changed: "place")
      expect(TicketShowChange.variables(fox)[:was]).to end_with("at Riverside Hall, Main room")
      expect(TicketShowChange.variables(fox)[:now]).to end_with("at Riverside Hall, Studio B")

      show.update!(location: create(:location, organization: org, name: "Annex"))
      expect(TicketShowChange.orders(listing)).to contain_exactly(dana, fox)
      expect(TicketShowChange.variables(dana)[:now]).to end_with("at Annex")
    end
  end

  describe "a student who was told no room" do
    let(:course) { create(:production, organization: org, name: "Improv 101", production_type: "course") }
    let(:offering) { create(:course_offering, production: course, title: "Improv 101", price_cents: 10_000) }
    let!(:session) { create(:show, production: course, course_offering: offering, event_type: "class", date_and_time: 10.days.from_now.change(hour: 19), location: hall) }

    it "is not asked about when the session is given its location's room" do
      user = create(:user)
      create(:person, user: user, email: "dana@example.com", name: "Dana Scully")
      registration = CourseCheckout.start!(offering: offering, user: user)
      CourseCheckoutSettlement.settle!(registration)
      registration.reload
      told = registration.told_sessions
      registration.update_columns(told_sessions: told.transform_values { |v| v.merge("space_id" => nil) })

      expect(CourseSessionChange.moved(registration.reload)).to be_empty
      expect(CourseSessionChange.pending?(offering)).to be(false)

      session.update!(location: create(:location, organization: org, name: "Annex"))
      expect(CourseSessionChange.moved(registration).sole.show).to eq(session)
    end
  end
end
