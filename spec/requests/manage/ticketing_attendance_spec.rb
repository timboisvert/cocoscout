# frozen_string_literal: true

require "rails_helper"

# Ticketing → Attendance (Tim, 2026-10-17): everyone holding a ticket, date
# by date, for a period, with a subtotal per production and each date's
# breakdown by source. Counts only: never money.
RSpec.describe "Ticketing attendance", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:boylesque) { create(:production, organization: org, name: "Boylesque") }
  let(:hags) { create(:production, organization: org, name: "Hags") }
  let(:week) { Date.current.beginning_of_week }
  let(:thursday) { (week + 3).in_time_zone.change(hour: 19, min: 30) }
  let(:friday) { (week + 4).in_time_zone.change(hour: 22) }
  let(:last_thursday) { (week - 4).in_time_zone.change(hour: 19, min: 30) }

  def listing_for(production, at)
    show = create(:show, production: production, date_and_time: at)
    create(:ticket_listing, organization: org, show: show)
  end

  def sell(listing, channel, count, status: "valid")
    tier = listing.ticket_tiers.first || create(:ticket_tier, ticket_listing: listing, name: "General")
    order = create(:ticket_order, ticket_listing: listing, status: "paid", channel: channel, paid_at: 1.day.ago)
    count.times { create(:ticket, ticket_order: order, ticket_tier: tier, status: status) }
  end

  let!(:thursday_listing) { listing_for(boylesque, thursday) }
  let!(:friday_listing) { listing_for(hags, friday) }
  let!(:last_week_listing) { listing_for(boylesque, last_thursday) }

  before do
    sell(thursday_listing, "online", 3)
    sell(thursday_listing, "door_cash", 2, status: "checked_in")
    sell(thursday_listing, "comp", 1)
    tailor = org.ticket_sources.create!(name: "Ticket Tailor")
    eventbrite = org.ticket_sources.create!(name: "Eventbrite")
    tier = thursday_listing.ticket_tiers.first
    thursday_listing.ticket_outside_sales.create!(organization: org, ticket_tier: tier, ticket_source: tailor, tickets_sold: 5, amount_cents: 0)
    thursday_listing.ticket_outside_sales.create!(organization: org, ticket_tier: tier, ticket_source: eventbrite, tickets_sold: 4, amount_cents: 8_000)
    sell(friday_listing, "online", 2)
    sell(last_week_listing, "online", 4)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "adds up this week's dates, by production, with each date's sources on hand" do
    get manage_ticketing_attendance_path
    expect(response).to have_http_status(:ok)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("17 people across 2 dates", "7 sold here", "9 on other sites, so far", "1 comp", "2 came through the door",
                            "Boylesque <span class=\"font-normal text-gray-500\">· 1 date</span>", "Hags <span")
    expect(html).to include("Online · 3", "Cash at the door · 2", "Ticket Tailor · 5", "Eventbrite · 4", "Comps · 1", "Came through the door · 2")
    expect(html).to include(manage_ticket_listing_path(thursday_listing), manage_ticket_listing_path(friday_listing))
    expect(html).not_to include(manage_ticket_listing_path(last_week_listing), "$80.00")
  end

  it "covers last week, the last seven days, and any two dates" do
    get manage_ticketing_attendance_path(filter: "last_week")
    expect(response.body).to include("4 people across 1 date", manage_ticket_listing_path(last_week_listing))

    get manage_ticketing_attendance_path(filter: "#{week - 7}..#{week + 6}")
    expect(response.body).to include("21 people across 3 dates")

    get manage_ticketing_attendance_path(from: (week - 7).to_s, to: (week + 6).to_s, production: boylesque.id)
    expect(response).to redirect_to(manage_ticketing_attendance_path(filter: "#{week - 7}..#{week + 6}", production: boylesque.id))
    follow_redirect!
    expect(response.body).to include("19 people across 2 dates")
    expect(response.body).not_to include(manage_ticket_listing_path(friday_listing))

    get manage_ticketing_attendance_path(filter: "nonsense..2026-99-99")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("17 people across 2 dates")
  end

  it "links from the Ticketing page" do
    get manage_ticketing_path
    expect(response.body).to include(manage_ticketing_attendance_path)
  end
end
