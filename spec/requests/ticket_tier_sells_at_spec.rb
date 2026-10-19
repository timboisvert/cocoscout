# frozen_string_literal: true

require "rails_helper"

# Where a ticket type sells (Tim, 2026-10-18): Burlioke is "Reserve a spot,
# $15, online only" and "At the door, $20, door only". The ticket page shows
# one, the door shows the other, and neither can be bought the wrong way.
RSpec.describe "Where a ticket type sells", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true) } }
  let(:production) { create(:production, organization: org, name: "Burlioke") }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 3.days.from_now.change(hour: 20))) }
  let!(:advance) { listing.ticket_tiers.create!(name: "Reserve a spot", price_cents: 1_500, quantity: 60, position: 0) }
  let!(:at_door) { listing.ticket_tiers.create!(name: "At the door", price_cents: 2_000, position: 1) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "is set on the Tickets tab, shows on the date's page, and keeps each type to its side" do
    patch manage_ticket_listing_path(listing), params: { ticket_listing: { ticket_tiers_attributes: {
      "0" => { id: advance.id, name: "Reserve a spot", price: "15", quantity: "60", sells_at: "online" },
      "1" => { id: at_door.id, name: "At the door", price: "20", quantity: "", sells_at: "door" }
    } } }
    expect(advance.reload.sells_at).to eq("online")
    expect(at_door.reload.sells_at).to eq("door")

    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Online only", "At the door only")

    get tickets_event_path(org: profile.slug, event: listing.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reserve a spot", "$15.00")
    expect(response.body).not_to include("At the door<", "$20.00")

    get door_path(listing)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("At the door", "$20.00")
    expect(response.body).not_to include("Reserve a spot")

    expect { TicketCheckout.start!(listing: listing, quantities: { at_door.id.to_s => "1" }) }.to raise_error(TicketCheckout::Error)
    expect { TicketCheckout.start!(listing: listing, quantities: { advance.id.to_s => "1" }, channel: "door_cash", at_door: true) }.to raise_error(TicketCheckout::Error)
    expect(TicketCheckout.start!(listing: listing, quantities: { advance.id.to_s => "1" }).tickets.size).to eq(1)
    expect(TicketCheckout.start!(listing: listing, quantities: { at_door.id.to_s => "1" }, channel: "door_cash", at_door: true).tickets.size).to eq(1)
  end

  it "comes down from the production's types to each date's" do
    setup = ProductionTicketing.for(production)
    setup.ticket_tiers.create!(name: "At the door", price_cents: 2_000, sells_at: "door", position: 1)
    setup.ticket_tiers.create!(name: "Reserve a spot", price_cents: 1_500, quantity: 60, sells_at: "online", position: 0)
    fresh = TicketListing.create!(show: create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 20)), status: "on_sale", inherits_tiers: true)
    ProductionTicketingSync.sync_all!(setup)
    expect(fresh.reload.ticket_tiers.active.order(:position).map { |t| [ t.name, t.sells_at ] })
      .to eq([ [ "Reserve a spot", "online" ], [ "At the door", "door" ] ])
  end

  it "defaults to everywhere, as before" do
    expect(advance.sells_at).to eq("everywhere")
    expect(advance).to be_sells_online
    expect(advance).to be_sells_at_door
    expect(advance.sells_at_words).to be_nil
  end
end
