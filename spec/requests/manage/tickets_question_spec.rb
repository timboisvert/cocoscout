# frozen_string_literal: true

require "rails_helper"

# The Tickets question (Round 9 §3): "Where do people get tickets for this
# production?", asked once on its page, three answers, applied by
# TicketsAnswer, shown on the show page too.
RSpec.describe "The Tickets question", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, email_address: "andie@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: manager) }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19)) }

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_path
  end

  it "asks on the production's Tickets tab, and selling on CocoScout lists every date and opens the box office" do
    get manage_production_path(production)
    expect(response.body).to include("Where people get tickets isn", edit_manage_production_path(production, tab: 7))
    expect(response.body).not_to include("Sell them on CocoScout")
    get edit_manage_production_path(production, tab: 7)
    expect(response.body).to include("Where do people get tickets for Boylesque?", "Sell them on CocoScout", "Somewhere else", "No tickets")
    expect(TicketingProfile.for(org).enabled?).to be(false)

    patch manage_production_tickets_path(production), params: { return_to: manage_production_path(production), tickets: {
      mode: "cocoscout", fee_mode: "buyer", schedule_mode: "immediate",
      tiers: { "0" => { name: "General", price: "20", seats: "60" }, "1" => { name: "VIP", price: "$35.00", seats: "10" } }
    } }
    expect(response).to redirect_to(manage_production_path(production))
    expect(flash[:notice]).to start_with("Boylesque is on sale on CocoScout. Share cocoscout.com/t/")

    setup = production.reload.production_ticketing
    expect([ production.tickets_mode, setup.enabled, setup.schedule_mode, setup.fee_mode ]).to eq([ "cocoscout", true, "immediate", "buyer" ])
    expect(setup.ticket_tiers.pluck(:name, :price_cents, :quantity)).to eq([ [ "General", 2_000, 60 ], [ "VIP", 3_500, 10 ] ])
    expect(show.reload.ticket_listing).to have_attributes(status: "on_sale")
    expect(show.ticket_listing.inventory.capacity).to eq(70)
    expect(TicketingProfile.for(org).reload.enabled?).to be(true)

    get manage_production_path(production)
    expect(response.body).to include("Sold on CocoScout", "1 upcoming date", "/t/#{ShortLink.canonical_for!(production).code}", "Open ticketing")

    # The show page shows where the tickets are, small, for reading only.
    get manage_production_show_path(production, show)
    expect(response.body).to include("On CocoScout", "of 70", manage_ticket_listing_path(show.ticket_listing))
    expect(response.body).not_to include("Give tickets", "Where do people get tickets")

    # A date answering for itself leaves the production's CocoScout sales; following it again rejoins.
    patch manage_show_path(production, show), params: { show: { tickets_override: "1", tickets_mode: "none" } }
    expect(show.reload.tickets_mode).to eq("none")
    expect(setup.reload.excluded_show_ids).to eq([ show.id ])
    expect(show.ticket_listing).to be_nil
    patch manage_show_path(production, show), params: { show: { tickets_override: "0" } }
    expect(setup.reload.excluded_show_ids).to eq([])
    expect(show.reload.ticket_listing).to have_attributes(status: "on_sale")
  end

  it "shows someone on the production who isn't an organization manager the numbers, without the link into Ticketing" do
    TicketsAnswer.apply!(production, mode: "cocoscout", tiers: [ { "name" => "General", "price" => "20", "seats" => "60" } ])
    viewer = create(:user, email_address: "viewer@sg.example", password: password)
    create(:organization_role, user: viewer, organization: org, company_role: "viewer")
    get signout_path
    post handle_signin_path, params: { email_address: viewer.email_address, password: password }
    post set_organization_path(id: org.id)

    get manage_production_show_path(production, show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("On CocoScout", "of 60")
    expect(response.body).not_to include(manage_ticket_listing_path(show.ticket_listing))
  end

  it "takes a pasted link, names the site and adds it to the ticket sources; a date can point somewhere else" do
    patch manage_production_tickets_path(production), params: { tickets: { mode: "elsewhere", url: "www.tickettailor.com/events/sg/55" } }
    expect(response).to redirect_to(manage_production_path(production))
    expect(flash[:notice]).to eq("Tickets for Boylesque are on Ticket Tailor.")
    expect(production.reload.attributes.values_at("tickets_mode", "tickets_url")).to eq([ "elsewhere", "https://www.tickettailor.com/events/sg/55" ])
    expect(org.ticket_sources.pluck(:name)).to include("Ticket Tailor")
    expect(TicketLink.for(show)).to have_attributes(kind: :outside, site: "Ticket Tailor")

    get manage_production_path(production)
    expect(response.body).to include("Tickets on Ticket Tailor", "Change")
    get manage_production_show_path(production, show)
    expect(response.body).to include("Sold on Ticket Tailor", "The production&#39;s link")

    # The date's own answer, from its Tickets tab: inherit, or set it for this date only.
    get manage_edit_show_path(production, show)
    expect(response.body).to include("Set tickets for this date only", "Sold on Ticket Tailor", 'name="show[tickets_override]"')
    patch manage_show_path(production, show), params: { show: { tickets_override: "1", tickets_mode: "elsewhere", tickets_url: "eventbrite.com/e/99" } }
    expect(response).to redirect_to(manage_show_path(production, show))
    expect(show.reload.attributes.values_at("tickets_mode", "tickets_url")).to eq([ "elsewhere", "https://eventbrite.com/e/99" ])
    expect(TicketLink.for(show).site).to eq("Eventbrite")
    get manage_production_show_path(production, show)
    expect(response.body).to include("Sold on Eventbrite", "This date&#39;s own link")

    patch manage_show_path(production, show), params: { show: { tickets_override: "0", tickets_mode: "elsewhere", tickets_url: "eventbrite.com/e/99" } }
    expect(show.reload.attributes.values_at("tickets_mode", "tickets_url")).to eq([ nil, nil ])
    expect(TicketLink.for(show).site).to eq("Ticket Tailor")

    patch manage_production_tickets_path(production), params: { tickets: { mode: "elsewhere", url: "nope" } }
    expect(flash[:alert]).to eq("Paste the link where people buy tickets.")

    patch manage_production_tickets_path(production), params: { tickets: { mode: "none" } }
    expect(production.reload.tickets_mode).to eq("none")
    get manage_production_path(production)
    expect(response.body).to include("No tickets")
  end

  it "needs Pro to sell here, refuses to leave CocoScout once tickets are sold, and never reaches another organization" do
    org.update!(comped_indefinitely: false)
    patch manage_production_tickets_path(production), params: { tickets: { mode: "cocoscout", tiers: { "0" => { name: "General", price: "20" } } } }
    expect(flash[:alert]).to eq("Selling tickets on CocoScout is part of Pro.")
    # A free plan sees the Pro pitch on both Tickets tabs, not the question.
    get edit_manage_production_path(production, tab: 7)
    expect(response.body).to include("Pro feature", "Your own box office")
    expect(response.body).not_to include("Where do people get tickets for Boylesque?")
    get manage_edit_show_path(production, show)
    expect(response.body).to include("Pro feature", "Your own box office")

    org.update!(comped_indefinitely: true)
    patch manage_production_tickets_path(production), params: { tickets: { mode: "cocoscout", tiers: { "0" => { name: "General", price: "20", seats: "60" } } } }
    listing = show.reload.ticket_listing
    order = TicketCheckout.start!(listing: listing, quantities: { listing.ticket_tiers.first.id.to_s => "1" })
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_q")
    patch manage_production_tickets_path(production), params: { tickets: { mode: "none" } }
    expect(flash[:alert]).to include("Close its sales in Ticketing first")
    expect(production.reload.tickets_mode).to eq("cocoscout")

    theirs = create(:production)
    patch manage_production_tickets_path(theirs), params: { tickets: { mode: "none" } }
    expect(response).to have_http_status(:not_found)
  end
end
