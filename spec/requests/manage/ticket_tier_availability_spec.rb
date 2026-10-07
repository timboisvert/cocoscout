# frozen_string_literal: true

require "rails_helper"

# Tim, 2026-10-07: like Ticket Tailor, a ticket type on one date can be
# marked sold out or hidden from the ⋯ menu on that date's ticketing page,
# for that date only, without touching its seats or the production's prices.
RSpec.describe "Ticket type availability on one date", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60, position: 0) }
  let!(:vip) { listing.ticket_tiers.create!(name: "Front Row VIP", price_cents: 4_000, quantity: 10, position: 1) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  # Like the browser: the change lands back on the date's page (which shows,
  # and so spends, its notice).
  def set(tier, availability)
    patch manage_ticket_listing_tier_availability_path(listing, tier), params: { availability: availability }
    notice = flash[:notice]
    alert = flash[:alert]
    follow_redirect! if response.redirect?
    [ notice, alert ]
  end

  def buy(tier)
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { tier.id => 1 } }
  end

  it "marks a type sold out from its row's menu: still on the ticket page, greyed, and nobody can buy it" do
    get manage_ticket_listing_path(listing)
    expect(response.body).to include(manage_ticket_listing_tier_availability_path(listing, vip), "Mark sold out", "Hide from the ticket page")

    notice, = set(vip, "sold_out")
    expect(request.path).to eq(manage_ticket_listing_path(listing))
    expect(notice).to eq("Front Row VIP is marked sold out for this date.")
    expect(vip.reload.availability).to eq("sold_out")
    expect(vip.quantity).to eq(10)

    get manage_ticket_listing_path(listing)
    expect(response.body).to match(%r{<tr class="whitespace-nowrap text-red-700">\s*<td class="px-5 py-2.5 text-red-700">\s*Front Row VIP\s*<span class="ml-1 text-xs font-medium">· Sold out</span>})
    expect(response.body).to include("Put back on sale")

    set(general, "unlisted")
    expect(response.body).to match(%r{<tr class="whitespace-nowrap text-gray-400">\s*<td class="px-5 py-2.5 text-gray-400">\s*General\s*<span class="ml-1 text-xs font-medium">· Hidden</span>})
    set(general, "on_sale")

    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to match(/data-name="Front Row VIP"[^>]*data-max="0"/)
    expect(response.body).to match(/data-name="General"[^>]*data-max="[1-9]/)

    expect { buy(vip) }.not_to change(TicketOrder, :count)
    expect(flash[:alert]).to eq("That ticket isn't on sale.")
    expect { buy(general) }.to change(TicketOrder, :count).by(1)
  end

  it "hides a type from the ticket page and the listing's data, then puts it back on sale" do
    notice, = set(vip, "unlisted")
    expect(notice).to eq("Front Row VIP is hidden from the ticket page for this date.")

    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).not_to include("Front Row VIP")
    expect(Ticketing::ListingPayload.for(listing.reload)[:tiers].map { |t| t[:name] }).to eq([ "General" ])
    expect { buy(vip) }.not_to change(TicketOrder, :count)

    notice, = set(vip, "on_sale")
    expect(notice).to eq("Front Row VIP is back on sale for this date.")
    expect { buy(vip) }.to change(TicketOrder, :count).by(1)
  end

  it "reads the date as sold out once nothing left can be bought, though seats remain" do
    expect(listing.inventory.sold_out?).to be(false)
    vip.update!(availability: "sold_out")
    expect(listing.reload.inventory.sold_out?).to be(false)
    general.update!(availability: "unlisted")
    expect(listing.reload.inventory.sold_out?).to be(true)
    expect(listing.inventory.remaining).to eq(70)
  end

  it "keeps the door from selling it, while a manager can still give it as a comp" do
    vip.update!(availability: "sold_out")
    door = TicketDoor.new(listing, owner)
    expect { door.sell({ vip.id.to_s => "1" }, kind: "cash") }.to raise_error(TicketCheckout::Error, "Pick at least one ticket.")

    comp = TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Walter", email: nil, tier: vip, quantity: 1) ], by: owner, email_them: false)
    expect(comp.first.tickets.sole.ticket_tier).to eq(vip)
  end

  it "sells a bundle only while its ticket type is on sale" do
    four = listing.ticket_tiers.create!(name: "Four of us", price_cents: 7_000, admits: 4, bundle_of_tier_id: general.id, position: 2)
    expect(four.available?).to be(true)

    general.update!(availability: "sold_out")
    expect(four.reload.marked_sold_out?).to be(true)
    expect { buy(four) }.not_to change(TicketOrder, :count)
  end

  it "survives the production's price changes: a date that follows the production keeps its own say" do
    TicketsAnswer.apply!(production, mode: "cocoscout", tiers: [ { "name" => "General", "price" => "20", "seats" => "60" } ])
    setup = production.reload.production_ticketing
    second = create(:show, production: production, date_and_time: 12.days.from_now.change(hour: 19, min: 30))
    ProductionTicketingDates.sync!(setup)
    copy = second.reload.ticket_listing.ticket_tiers.sole
    copy.update!(availability: "sold_out")

    setup.ticket_tiers.sole.update!(price_cents: 2_500)
    ProductionTicketingSync.sync!(second.ticket_listing.reload)

    expect(copy.reload.price_cents).to eq(2_500)
    expect(copy.availability).to eq("sold_out")
  end

  it "refuses an unknown status, and another organization's dates" do
    _, alert = set(vip, "door_only")
    expect(alert).to eq("Pick on sale, sold out or hidden.")
    expect(vip.reload.availability).to eq("on_sale")

    theirs = TicketListing.create!(show: create(:show, production: create(:production, organization: create(:organization, :pro)), date_and_time: 3.days.from_now), status: "on_sale")
    their_tier = theirs.ticket_tiers.create!(name: "General", price_cents: 1_000, quantity: 10)
    patch manage_ticket_listing_tier_availability_path(theirs, their_tier), params: { availability: "sold_out" }
    expect(response).to have_http_status(:not_found)
    expect(their_tier.reload.availability).to eq("on_sale")

    other_date = TicketListing.create!(show: create(:show, production: production, date_and_time: 9.days.from_now), status: "on_sale")
    patch manage_ticket_listing_tier_availability_path(other_date, vip), params: { availability: "sold_out" }
    expect(response).to have_http_status(:not_found)
  end
end
