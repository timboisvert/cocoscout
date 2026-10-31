# frozen_string_literal: true

require "rails_helper"

# Seating (advanced ticketing plan §1, V1.4 step 4a): a chart drawn for a
# room, zones on it for the production's ticket types, the inventory that
# counts seats, best available, and the box office's seat map with holds.
RSpec.describe "Seating", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let!(:location) { create(:location, organization: org, name: "The Lodge") }
  let(:room) { location.default_room }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true) }
  let!(:premium) { setup.ticket_tiers.create!(name: "Premium", price_cents: 4_000, position: 0) }
  let!(:general) { setup.ticket_tiers.create!(name: "General", price_cents: 2_500, position: 1) }
  let!(:show) { create(:show, production: production, location: location, date_and_time: 20.days.from_now.change(hour: 19)) }
  let(:listing) { ProductionTicketingDates.sync!(setup); TicketListing.find_by!(show: show) }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  def draw_chart
    post manage_seat_charts_path, params: { seat_chart: { location_space_id: room.id, name: "Concert layout" } }
    chart = SeatChart.last
    post manage_sections_seat_chart_path(chart), params: { seat_section: { name: "Orchestra", kind: "rows", rows: 3, per_row: 6, first_row: "A", first_number: 1 } }
    post manage_sections_seat_chart_path(chart), params: { seat_section: { name: "Balcony", kind: "rows", rows: 2, per_row: 4, first_row: "AA", first_number: 101 } }
    post manage_sections_seat_chart_path(chart), params: { seat_section: { name: "Floor", kind: "standing", standing_capacity: 40 } }
    post manage_status_seat_chart_path(chart, status: "active")
    chart.reload
  end

  def zone!(chart)
    orchestra, balcony, floor = chart.sections.to_a
    patch manage_update_production_ticketing_path(production, section: "seating"),
          params: { production_ticketing: { seating_mode: "mixed", seat_chart_id: chart.id }, zones_present: "1",
                    zones: { premium.id => [ orchestra.id ], general.id => [ balcony.id, floor.id ] } }
    [ orchestra, balcony, floor ]
  end

  it "draws a chart for a room from Rooms and seating, marks seats, and makes it active" do
    get manage_ticketing_settings_path(section: "rooms")
    expect(response.body).to include("Draw one for this room", manage_new_seat_chart_path(room_id: room.id))
    get manage_new_seat_chart_path(room_id: room.id)
    expect(response.body).to include("A chart for Main room")

    chart = draw_chart
    expect(chart).to have_attributes(status: "active", seat_count: 26, standing_capacity: 40, kind: "mixed")
    orchestra = chart.sections.first
    expect(orchestra.rows.map(&:first)).to eq(%w[A B C])
    expect(orchestra.seats.pluck(:label)).to include("A 1", "C 6")
    expect(chart.sections.second.seats.pluck(:label)).to include("AA 101", "AB 104")
    # Laid out: the balcony sits below the orchestra, every seat has a place.
    expect(chart.sections.second.y).to be > orchestra.y
    expect(orchestra.seats.pluck(:x).uniq.size).to eq(6)
    # Best rank: the middle of the front row first.
    expect(orchestra.seats.min_by(&:best_rank).row_label).to eq("A")

    get manage_seat_chart_path(chart)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Concert layout", "Orchestra", "Balcony", "Floor", "data-seat-map-payload-value", "Wheelchair space")

    a1, a2 = orchestra.seats.where(row_label: "A").order(:number).first(2)
    patch manage_seats_seat_chart_path(chart), params: { seat_ids: [ a1.id ], kind: "wheelchair" }
    patch manage_seats_seat_chart_path(chart), params: { seat_ids: [ a2.id ], killed: "1" }
    expect(a1.reload).to have_attributes(kind: "wheelchair", accessible?: true)
    expect(a2.reload.killed).to be(true)
    expect(chart.seat_count).to eq(25)

    # The room's settings now offer it as the default chart.
    patch manage_ticketing_settings_room_path(room), params: { room_ticketing_setting: { seating_mode: "reserved", default_seat_chart_id: chart.id } }
    expect(RoomTicketingSetting.for(room)).to have_attributes(seating_mode: "reserved", default_seat_chart_id: chart.id)
    get manage_ticketing_settings_path(section: "rooms")
    expect(response.body).to include("Concert layout (25 seats, 40 standing)")
  end

  it "sells by the seat once the production picks the chart and zones, and counts seats, holds and standing room" do
    chart = draw_chart
    orchestra, balcony, floor = zone!(chart)
    expect(setup.reload).to have_attributes(seating_mode: "mixed", seat_chart_id: chart.id)
    expect(premium.reload.zone_section_ids).to eq([ orchestra.id ])
    expect(general.reload.zone_section_ids).to contain_exactly(balcony.id, floor.id)
    get manage_edit_production_ticketing_path(production, section: "seating")
    expect(response.body).to include("Zones on Concert layout", "zone-#{premium.id}-#{orchestra.id}")

    expect(listing.seated?).to be(true)
    expect(listing.effective_seating_mode).to eq("mixed")
    # The date's copies of the types follow the production's zones.
    date_premium = listing.ticket_tiers.find_by!(source_tier_id: premium.id)
    date_general = listing.ticket_tiers.find_by!(source_tier_id: general.id)
    expect(date_premium.zone_section_ids).to eq([ orchestra.id ])

    inventory = listing.inventory
    expect(inventory.capacity).to eq(66)
    expect(inventory.remaining).to eq(66)
    expect(inventory.remaining(tier: date_premium)).to eq(18)
    expect(inventory.remaining(tier: date_general)).to eq(48)

    # Hold four orchestra seats from the seat map.
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Seat map")
    get manage_ticket_listing_seats_path(listing)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hold seats", "Concert layout", "Premium")
    a_row = orchestra.seats.where(row_label: "A").order(:number).to_a
    post manage_ticket_listing_seat_holds_path(listing), params: { seat_ids: a_row.first(4).map(&:id), kind: "house", name: "Press night" }
    hold = listing.seat_holds.last
    expect(hold).to have_attributes(name: "Press night", kind: "house")
    expect(hold.hold_seats.count).to eq(4)
    expect(listing.inventory.remaining(tier: date_premium)).to eq(14)
    expect(listing.inventory.fits?({ date_premium => 15 })).to be(false)
    expect(listing.inventory.fits?({ date_premium => 14, date_general => 48 })).to be(true)

    # The same seat can't be held twice.
    post manage_ticket_listing_seat_holds_path(listing), params: { seat_ids: [ a_row.first.id ], kind: "manual" }
    expect(flash[:alert]).to include("already sold or held")

    get manage_ticket_listing_seats_path(listing, format: :json)
    payload = response.parsed_body
    held = payload["sections"].first["seats"].select { |s| s["status"] == "held" }
    expect(held.size).to eq(4)
    expect(held.first["hold"]["name"]).to eq("Press night")
    expect(payload["sections"].first["tier_name"]).to eq("Premium")
    expect(payload["sections"].last["standing_remaining"]).to eq(40)

    # Best available: a block together in the best row that has room.
    pick = Ticketing::BestAvailable.pick(listing, date_premium, 2)
    expect(pick.together).to be(true)
    expect(pick.seats.map(&:label)).to eq([ "A 5", "A 6" ])
    expect(pick.seats.map(&:row_label).uniq).to eq([ "A" ])
    three = Ticketing::BestAvailable.pick(listing, date_premium, 3)
    expect(three.together).to be(true)
    expect(three.seats.map(&:row_label).uniq).to eq([ "B" ])
    expect(three.seats.map(&:number)).to eq([ 2, 3, 4 ])
    expect(Ticketing::BestAvailable.pick(listing, date_premium, 15)).to be_nil

    # Reserving named seats under the lock; a held seat is refused.
    b_row = orchestra.seats.where(row_label: "B").order(:number).to_a
    expect {
      Ticketing::Inventory.reserve!(listing, { date_premium => 1 }, seats: { date_premium => [ a_row.first.id ] }) { }
    }.to raise_error(Ticketing::Inventory::SoldOut)
    expect {
      Ticketing::Inventory.reserve!(listing, { date_premium => 1 }, seats: { date_premium => [ b_row.first.id ] }) { }
    }.not_to raise_error
    # A seat outside the type's zone is refused too.
    expect {
      Ticketing::Inventory.reserve!(listing, { date_general => 1 }, seats: { date_general => [ b_row.first.id ] }) { }
    }.to raise_error(Ticketing::Inventory::SoldOut)

    # Release the hold: the seats come back.
    delete manage_ticket_listing_seat_hold_path(listing, hold)
    expect(hold.reload.released_at).to be_present
    expect(listing.inventory.remaining(tier: date_premium)).to eq(18)

    # One date can choose for itself.
    patch manage_ticket_listing_path(listing), params: { section: "seating", ticket_listing: { seating_mode: "general", seat_chart_id: "" } }
    expect(listing.reload.seated?).to be(false)
    expect(listing.inventory.capacity).to be_nil
    get manage_edit_ticket_listing_path(listing, section: "seating")
    expect(response.body).to include("general admission")
  end

  it "keeps a chart that is in use, and lets an unused one go" do
    chart = draw_chart
    zone!(chart)
    delete manage_seat_chart_path(chart)
    expect(flash[:alert]).to include("in use")
    expect(SeatChart.exists?(chart.id)).to be(true)

    spare = org.seat_charts.create!(location_space: room, name: "Spare")
    delete manage_seat_chart_path(spare)
    expect(SeatChart.exists?(spare.id)).to be(false)
  end
end
