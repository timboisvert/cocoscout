# frozen_string_literal: true

require "rails_helper"

# Ticketing's home: sales for a period, what needs the theater, each
# production's next date with how it's selling (its later dates in a
# drawer), and what just played.
RSpec.describe "Ticketing dashboard", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs") }

  before do
    create(:organization_role, :manager, user: superadmin, organization: org)
    TicketingProfile.for(org).update!(enabled: true, slug: "starsandgarters")
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  def listing_at(time, status: "on_sale")
    listing = TicketListing.create!(show: create(:show, production: production, date_and_time: time), status: status)
    listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50)
    listing
  end

  def buy(listing, count, name, at: Time.current)
    travel_to(at) do
      order = TicketCheckout.start!(listing: listing, quantities: { listing.ticket_tiers.first.id.to_s => count.to_s })
      order.update!(buyer_name: name, buyer_email: "#{name.parameterize}@example.com")
      TicketOrderSettlement.settle!(order)
      order
    end
  end

  it "shows sales, upcoming shows with their numbers, and what just played" do
    upcoming = listing_at(5.days.from_now.change(hour: 19, min: 30))
    played = listing_at(3.days.ago.change(hour: 19, min: 30))
    buy(played, 4, "Fox Mulder", at: 6.days.ago)
    buy(upcoming, 3, "Dana Scully")

    get manage_ticketing_path(period: "all_time")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tickets sold", "Ticket sales", "$140.00", "Coming up", "of 50", "· $60",
                                      "Just played", "4 sold", "/t/#{ShortLink.canonical_for!(TicketingProfile.for(org)).code}", "Taxes collected", "Embed on your website")
    expect(response.body).to include(manage_ticket_listing_path(upcoming), manage_ticket_listing_path(played))
    expect(response.body).not_to include("Latest orders", "this week")
  end

  it "shows each production once, at its next date, soonest first, with its later dates behind a drawer" do
    later_production = create(:production, organization: org, name: "Laugh Along Live")
    first = (1..8).map { |n| listing_at((n * 2).days.from_now.change(hour: 19, min: 30)) }
    other = TicketListing.create!(show: create(:show, production: later_production, date_and_time: 3.days.from_now.change(hour: 21)), status: "on_sale")
    other.ticket_tiers.create!(name: "General", price_cents: 1_500, quantity: 40)

    rows = TicketingDashboard.new(org).coming_up
    expect(rows.map { |row| row.production.name }).to eq([ "Improvised Animorphs", "Laugh Along Live" ])
    expect(rows.first.next_listing).to eq(first.first)
    expect(rows.first.dates.size).to eq(TicketingDashboard::DATES_PER_PRODUCTION)
    expect(rows.first.total).to eq(8)
    expect(rows.last.later).to be_empty

    get manage_ticketing_path
    body = response.body
    expect(body).not_to include("2 productions, 9 dates")
    expect(body).to include("7 more dates", "All 8 dates of Improvised Animorphs",
                            manage_production_ticketing_path(production), manage_ticket_listing_path(first[5]))
    expect(body).not_to include(manage_ticket_listing_path(first[6]))
    expect(body.index("Improvised Animorphs")).to be < body.index("Laugh Along Live")
  end

  it "counts only the period chosen" do
    listing = listing_at(10.days.from_now)
    buy(listing, 2, "Old Order", at: 40.days.ago)
    buy(listing, 1, "New Order")

    dashboard = TicketingDashboard.new(org, period: :last_30_days)
    expect([ dashboard.summary.tickets, dashboard.summary.gross_cents ]).to eq([ 1, 2_000 ])
    expect(TicketingDashboard.new(org, period: :all_time).summary.tickets).to eq(3)
    expect(TicketingDashboard.new(org, period: :nonsense).period).to eq(:last_30_days)
  end

  it "nudges about drafts coming up and a canceled show with ticket holders; tonight is only the Door's count" do
    tonight = listing_at(Time.current.end_of_day - 1.hour)
    buy(tonight, 2, "Tonight Guest")
    listing_at(6.days.from_now, status: "draft")
    canceled = listing_at(9.days.from_now)
    buy(canceled, 1, "Holder")
    canceled.show.update!(canceled: true)

    get manage_ticketing_path
    # No box for tonight (Tim, 2026-10-09): the Door section's badge counts it.
    expect(response.body).not_to include("Open the door", "Sell tickets for a production")
    expect(TicketingDashboard.new(org).tonight.map(&:first)).to eq([ tonight ])
    expect(response.body).to include("is canceled but people hold tickets")
    expect(response.body).to include("1 show in the next two weeks isn&#39;t on sale")
  end

  it "says the box office isn't open until they open it" do
    TicketingProfile.for(org).update!(enabled: false)
    get manage_ticketing_path
    expect(response.body).to include("Your box office isn&#39;t open yet", manage_ticketing_settings_section_path(section: "box_office"))
  end
end
