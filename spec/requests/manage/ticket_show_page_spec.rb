# frozen_string_literal: true

require "rails_helper"

# A show's own ticketing page: the numbers, the guest list (searchable, as a
# CSV, and on paper), and giving tickets away.
RSpec.describe "Manage a show's tickets", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, owner: superadmin) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 40) }

  before do
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  def buy(count, name)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: name, buyer_email: "#{name.parameterize}@example.com")
    TicketOrderSettlement.settle!(order)
    order.reload
  end

  it "shows the numbers and the guest list, filtered and searched" do
    dana = buy(2, "Dana Scully")
    buy(1, "Fox Mulder")
    TicketDoor.new(listing, superadmin).check_in(dana.tickets.first.code)

    get manage_ticket_listing_path(listing)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("3 of 40", "$60.00", "By ticket type", "Guest list", "Dana Scully", "Fox Mulder", "1 of 2 in")

    get manage_ticket_listing_path(listing, guests: "in")
    expect(response.body).to include("Dana Scully")
    expect(response.body).not_to include("Fox Mulder")

    get manage_ticket_listing_path(listing, q: "fox")
    expect(response.body).to include("Fox Mulder")
    expect(response.body).not_to include("Dana Scully")
  end

  it "downloads the guest list and prints a door list by last name" do
    buy(2, "Dana Scully")
    buy(1, "Fox Mulder")

    get manage_ticket_listing_guests_path(listing, format: :csv)
    expect(response.media_type).to eq("text/csv")
    lines = response.body.lines.map(&:strip)
    expect(lines.first).to start_with("Name,Email,Phone,Order,Tickets")
    expect(lines).to include(a_string_starting_with("Dana Scully,dana-scully@example.com,,"))

    get manage_ticket_listing_door_list_path(listing)
    expect(response.body).to include("Door list", "3 tickets")
    expect(response.body.index("Fox Mulder")).to be < response.body.index("Dana Scully")
  end

  # Tim (2026-10-02): one person at a time, no pasted list. Tim (2026-10-06):
  # the form is a modal behind the Comps tile, not its own page.
  it "gives tickets away one person at a time, from the Comps tile, and says so" do
    get manage_ticket_listing_path(listing)
    expect(response.body).to include('data-modal-id="comps-modal"', 'id="comps-modal"', 'name="name"', 'name="quantity"')
    expect(response.body).not_to include("One person per line")
    # One ticket type: said, not chosen. Emailing asks for their email, and needs it.
    expect(response.body).to include(%(type="hidden" name="tier_id" id="comp_tier_id" value="#{general.id}"), "General ($20.00) · 40 left",
                                     "Email them their tickets", 'name="email_them"')
    expect(response.body).to match(/id="comp_email"[^>]*required="required"/)
    expect(response.body).not_to include('<select name="tier_id"')
    listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500, quantity: 10)
    get manage_ticket_listing_path(listing)
    expect(response.body).to include('<select name="tier_id" id="comp_tier_id"')
    get manage_new_ticket_listing_comps_path(listing)
    expect(response).to redirect_to(manage_ticket_listing_path(listing, anchor: "guests"))

    expect {
      post manage_ticket_listing_comps_path(listing),
           params: { name: "Walter Skinner", email: "walter@example.com", quantity: "2", tier_id: general.id, note: "Press", email_them: "1" }
    }.to have_enqueued_job(TicketOrderConfirmationJob).once
    expect(response).to redirect_to(manage_ticket_listing_path(listing, anchor: "guests"))
    expect(flash[:notice]).to start_with("Gave 2 tickets to Walter Skinner.")

    expect {
      post manage_ticket_listing_comps_path(listing), params: { name: "Monica Reyes", quantity: "1", tier_id: general.id, email_them: "0" }
    }.not_to have_enqueued_job(TicketOrderConfirmationJob) # handed over in person

    # Email them, with nowhere to send: refused, nothing given.
    expect {
      post manage_ticket_listing_comps_path(listing), params: { name: "No Address", quantity: "1", tier_id: general.id, email_them: "1", email: "" }
    }.not_to change { listing.ticket_orders.where(channel: "comp").count }
    expect(flash[:alert]).to eq("Add their email to send their tickets, or switch off Email them their tickets.")
    get manage_ticket_listing_path(listing, guests: "comps")
    expect(response.body).to include("Walter Skinner", "Monica Reyes", "Comp")

    post manage_ticket_listing_comps_path(listing), params: { name: "Too Many", quantity: "50", tier_id: general.id }
    expect(response).to redirect_to(manage_ticket_listing_path(listing, anchor: "guests"))
    expect(flash[:alert]).to match(/\AGeneral has only \d+ seats? left\.\z/)
  end

  it "goes back where it came from after a status change" do
    post manage_ticket_listing_status_path(listing, status: "paused"), headers: { "HTTP_REFERER" => manage_ticket_listing_url(listing) }
    expect(response).to redirect_to(manage_ticket_listing_url(listing))
    expect(listing.reload.status).to eq("paused")
  end
end
