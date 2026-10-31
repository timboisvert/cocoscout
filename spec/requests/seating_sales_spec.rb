# frozen_string_literal: true

require "rails_helper"

# Seating, selling (advanced ticketing plan §1, V1.4 step 4b): seats picked
# on the map or chosen for the buyer, named on the checkout, the order, the
# ticket, the PDF and the door; moves; comps from the map; refunds and
# exchanges that give seats back.
RSpec.describe "Seating sales", type: :request do
  include ActiveJob::TestHelper

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
  let!(:other_show) { create(:show, production: production, location: location, date_and_time: 21.days.from_now.change(hour: 19)) }
  let(:chart) do
    chart = org.seat_charts.create!(location_space: room, name: "Concert layout")
    orchestra = chart.sections.create!(name: "Orchestra", kind: "rows", position: 0)
    orchestra.add_rows!(count: 2, per_row: 6, first_row: "A", first_number: 1)
    floor = chart.sections.create!(name: "Floor", kind: "standing", position: 1, standing_capacity: 10)
    chart.relayout!
    chart.update!(status: "active")
    orchestra.seats.find_by!(row_label: "A", number: 1).update!(kind: "wheelchair")
    orchestra.seats.find_by!(row_label: "A", number: 2).update!(kind: "companion")
    premium.zones.create!(seat_section: orchestra)
    general.zones.create!(seat_section: floor)
    setup.update!(seating_mode: "mixed", seat_chart: chart)
    chart
  end
  let(:orchestra) { chart.sections.first }
  let(:floor) { chart.sections.last }
  let(:listing) { chart; ProductionTicketingDates.sync!(setup); TicketListing.find_by!(show: show) }
  let(:other) { listing; TicketListing.find_by!(show: other_show) }
  let(:date_premium) { listing.ticket_tiers.find_by!(source_tier_id: premium.id) }
  let(:date_general) { listing.ticket_tiers.find_by!(source_tier_id: general.id) }

  def seat(label)
    row, number = label.split
    orchestra.seats.find_by!(row_label: row, number: number)
  end

  def pay!(order)
    order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{order.id}")
    order.reload
  end

  before do
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
  end

  it "sells the seats a buyer picks on the map, names them everywhere, and keeps accessible seats for people who need them" do
    get tickets_event_path(org: profile.slug, event: listing.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pick your seats", "Best available", "data-seat-map-mode-value=\"buy\"", "needs accessible seating")

    # Two orchestra seats by hand.
    post tickets_start_checkout_path(org: profile.slug, event: listing.slug), params: { seat_ids: [ seat("B 3").id, seat("B 4").id ] }
    order = TicketOrder.last
    expect(response).to redirect_to(tickets_checkout_path(token: order.token))
    expect(order.tickets.map(&:seat_label)).to contain_exactly("B 3", "B 4")
    expect(order.tickets.map(&:ticket_tier_id).uniq).to eq([ date_premium.id ])
    follow_redirect!
    expect(response.body).to include("B 3, B 4")

    # The same seat can't go twice.
    post tickets_start_checkout_path(org: profile.slug, event: listing.slug), params: { seat_ids: [ seat("B 3").id ] }
    expect(flash[:alert]).to include("just taken")

    # The wheelchair space waits for someone who needs it while other seats are free.
    post tickets_start_checkout_path(org: profile.slug, event: listing.slug), params: { seat_ids: [ seat("A 1").id ] }
    expect(flash[:alert]).to include("kept for people who need accessible seating")
    post tickets_start_checkout_path(org: profile.slug, event: listing.slug), params: { seat_ids: [ seat("A 1").id, seat("A 2").id ], accessible: "1" }
    accessible_order = TicketOrder.last
    expect(accessible_order.tickets.map(&:seat_label)).to contain_exactly("A 1", "A 2")

    # Best available picks for the buyer: the best pair still together, never the accessible seats.
    post tickets_start_checkout_path(org: profile.slug, event: listing.slug), params: { quantities: { date_premium.id.to_s => "2", date_general.id.to_s => "1" } }
    best = TicketOrder.last
    expect(best.tickets.where(ticket_tier: date_premium).map(&:seat_label)).to eq([ "A 3", "A 4" ])
    expect(best.tickets.where(ticket_tier: date_general).first).to have_attributes(seat_id: nil, seat_section_id: floor.id, seat_label: "Floor")
    expect(listing.inventory.remaining(tier: date_general)).to eq(9)

    pay!(order)
    expect(order.status).to eq("paid")
    get tickets_order_path(token: order.token)
    expect(response.body).to include("B 3", "B 4")
    ticket = order.tickets.order(:id).first
    get tickets_ticket_path(code: ticket.code)
    expect(response.body).to include("B 3")
    pdf = TicketPdf.new(order).render
    expect(pdf.bytesize).to be > 1000

    # The door hears the seat.
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
    travel_to(show.date_and_time - 2.hours) do
      post door_check_in_path(listing), params: { code: ticket.code }, as: :json
    end
    expect(response.parsed_body["seat"]).to eq("B 3")
    expect(response.parsed_body["kind"]).to eq("admitted")

    # A refund gives the seat back; a hold of an expired checkout too.
    TicketOrderRefund.issue!(order, ticket_ids: [ order.tickets.order(:id).last.id ])
    expect(Ticketing::Seating.new(listing).taken?(seat("B 4").id)).to be(false)
    expect(Ticketing::Seating.new(listing).taken?(seat("B 3").id)).to be(true)
    best.update!(expires_at: 1.minute.ago)
    expect(Ticketing::Seating.new(listing).taken?(seat("A 3").id)).to be(false)

    expect(BooksReconciliation.check(org)).to eq([])
  end

  it "moves a ticket from the seat map, comps picked seats, and gives seats to an exchange" do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
    order = pay!(TicketCheckout.start!(listing: listing, quantities: { date_premium.id.to_s => "1" }, seats: [ seat("B 1").id ]))
    ticket = order.tickets.first
    expect(ticket.seat_label).to eq("B 1")

    get manage_ticket_listing_seats_path(listing)
    expect(response.body).to include("Move a ticket", "Comp these seats")
    perform_enqueued_jobs do
      post manage_ticket_listing_seat_move_path(listing), params: { ticket_id: ticket.id, seat_id: seat("B 6").id, email: "1" }
    end
    expect(flash[:notice]).to include("moved to B 6")
    expect(ticket.reload.seat_label).to eq("B 6")
    moved = ActionMailer::Base.deliveries.find { |m| m.subject.include?("Your seats changed") }
    expect(moved).to be_present
    expect(moved.html_part.body.to_s).to include("B 1 is now B 6")
    # Comps in exactly those seats.
    post manage_ticket_listing_seat_comps_path(listing), params: { seat_ids: [ seat("A 5").id, seat("A 6").id ], name: "Press", email: "press@example.com" }
    expect(flash[:notice]).to include("2 seats given to Press")
    comp = TicketOrder.where(channel: "comp").last
    expect(comp.tickets.map(&:seat_label)).to contain_exactly("A 5", "A 6")

    # A taken seat is refused.
    post manage_ticket_listing_seat_move_path(listing), params: { ticket_id: ticket.id, seat_id: seat("A 5").id }
    expect(flash[:alert]).to include("taken")

    # Exchanged to the other date: a seat there, the old one free.
    exchange = TicketOrderExchange.exchange!(order.reload, target: other, email_them: false)
    new_ticket = exchange.to_order.tickets.first
    expect(new_ticket.ticket_listing).to eq(other)
    expect(new_ticket.seat_label).to eq("A 3")
    expect(Ticketing::Seating.new(listing).taken?(seat("B 6").id)).to be(false)

    expect(BooksReconciliation.check(org)).to eq([])
  end
end
