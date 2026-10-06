# frozen_string_literal: true

require "rails_helper"

# One ticket link, everywhere a show is listed (Round 9 §3): the Tickets chip
# on show rows, Get tickets on the public production and show pages.
RSpec.describe "The ticket link everywhere", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, email_address: "andie@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: manager) }
  let(:production) { create(:production, organization: org, name: "Boylesque", public_profile_enabled: true, public_key: "boylesque") }
  let!(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19), public_profile_visible: true) }
  let!(:elsewhere) { create(:production, organization: org, name: "Open Mic", public_profile_enabled: true, public_key: "openmic", tickets_mode: "elsewhere", tickets_url: "https://www.eventbrite.com/e/mic") }
  let!(:mic_night) { create(:show, production: elsewhere, date_and_time: 4.days.from_now.change(hour: 20), public_profile_visible: true) }

  def sell!
    TicketingProfile.for(org).update!(enabled: true, slug: "starsandgarters")
    listing = TicketListing.create!(show: show, status: "on_sale")
    listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
    production.update!(tickets_mode: "cocoscout")
    listing
  end

  it "leaves the manager's Shows & Events list alone: no chips, no nudge (Tim, 2026-10-06)" do
    sell!
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_path

    get manage_shows_path
    expect(response.body).not_to include("Where do people get tickets", "Tickets · Eventbrite", "data-tooltip-text=\"Get tickets\"")
  end

  it "puts Get tickets on the public production and show pages, only while the box office is open" do
    get public_profile_path("openmic")
    expect(response.body).to include("Get tickets", "https://www.eventbrite.com/e/mic")

    get public_profile_path("boylesque")
    expect(response.body).not_to include("Get tickets")

    listing = sell!
    get public_profile_path("boylesque")
    expect(response.body).to include("Get tickets", "/t/#{ShortLink.canonical_for!(production).code}")
    get public_profile_show_path("boylesque", show.id)
    expect(response.body).to include("Get tickets", "On sale now.", "/t/#{ShortLink.canonical_for!(production).code}/#{ShortLink.date_suffix(show)}")

    TicketingProfile.for(org).update!(enabled: false)
    get public_profile_path("boylesque")
    expect(response.body).not_to include("Get tickets")
    expect(listing.reload.status).to eq("on_sale") # the listing is untouched; only the public link hides
  end
end
