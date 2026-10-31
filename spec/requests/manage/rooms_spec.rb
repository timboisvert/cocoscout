# frozen_string_literal: true

require "rails_helper"

# Rooms on every plan (advanced ticketing plan §0): every location has a
# room, a show lands in one, each room has a page, and Ticketing keeps its
# per-room seating settings in its own table and its own settings tab.
RSpec.describe "Rooms", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org, name: "The Lincoln Lodge") }
  let!(:production) { create(:production, organization: org, name: "Holiday Revue") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "gives a new location a Main room, and a new show lands in the default room" do
    expect(location.location_spaces.pluck(:name, :default)).to eq([ [ "Main room", true ] ])
    show = create(:show, production: production, location: location)
    expect(show.location_space).to eq(location.default_room)
    online = create(:show, :online, production: production)
    expect(online.location_space).to be_nil
  end

  it "lists rooms on the location page and gives each room its own page" do
    room = location.location_spaces.create!(name: "The Lounge", capacity: 80, description: "Downstairs.")
    show = create(:show, production: production, location: location, location_space: room, date_and_time: 3.days.from_now)

    get manage_location_path(location)
    expect(response.body).to include("Rooms", "Main room", "The Lounge", "Up to 80 people", manage_location_space_path(location, room))
    expect(response.body).not_to include("Spaces")

    get manage_location_space_path(location, room)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("The Lounge", "Most people allowed", "80", "Coming up in this room", show.display_name, "Tickets in this room", "General admission")

    patch manage_location_space_path(location, room), params: { location_space: { name: "The Lounge", capacity: 90, default: "1" } }
    expect(response).to redirect_to(manage_location_space_path(location, room))
    expect(room.reload.capacity).to eq(90)
    expect(room).to be_default
    expect(location.location_spaces.find_by(name: "Main room")).not_to be_default
  end

  it "keeps at least one room per location and never deletes a room with shows" do
    only = location.default_room
    delete manage_location_space_path(location, only)
    expect(location.location_spaces.count).to eq(1)
    expect(flash[:alert]).to include("at least one room")

    room = location.location_spaces.create!(name: "Studio")
    create(:show, production: production, location: location, location_space: room)
    delete manage_location_space_path(location, room)
    expect(room.reload).to be_persisted
    expect(flash[:alert]).to include("shows or bookings")
  end

  it "caps a general admission show at the room's limit when its ticket types have no counts" do
    room = location.default_room.tap { |r| r.update!(capacity: 3) }
    show = create(:show, production: production, location: location, location_space: room)
    listing = TicketListing.create!(show: show, status: "on_sale")
    tier = listing.ticket_tiers.create!(name: "General", price_cents: 2_000)
    expect(listing.inventory.capacity).to eq(3)
    expect(listing.inventory.remaining(tier: tier)).to eq(3)

    tier.update!(quantity: 10)
    expect(listing.inventory.capacity).to eq(10)
  end

  it "has a Rooms and seating tab in Ticketing settings that saves how each room sells" do
    room = location.default_room
    get manage_ticketing_settings_section_path(section: "rooms")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rooms and seating", "The Lincoln Lodge", "Main room", "Reserved seats", "Directions for buyers")

    patch manage_ticketing_settings_room_path(room), params: { room_ticketing_setting: { seating_mode: "reserved", buyer_directions: "Enter on Clark Street." } }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "rooms"))
    setting = RoomTicketingSetting.find_by!(location_space: room)
    expect(setting.seating_mode).to eq("reserved")
    expect(setting.buyer_directions).to eq("Enter on Clark Street.")
    expect(room.reload.attributes.keys).not_to include("seating_mode")

    get manage_location_space_path(location, room)
    expect(response.body).to include("Reserved seats", "Enter on Clark Street.")
  end
end
