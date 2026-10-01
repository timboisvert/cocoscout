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

  it "gives tickets away and says so" do
    get manage_new_ticket_listing_comps_path(listing)
    expect(response.body).to include("One person per line")

    expect {
      post manage_ticket_listing_comps_path(listing),
           params: { guests: "Walter Skinner, walter@example.com, 2\nMonica Reyes", tier_id: general.id, note: "Press", email_them: "1" }
    }.to have_enqueued_job(TicketOrderConfirmationJob).once
    expect(response).to redirect_to(manage_ticket_listing_path(listing, anchor: "guests"))
    expect(flash[:notice]).to eq("Gave 3 tickets to 2 people.")

    get manage_ticket_listing_path(listing, guests: "comps")
    expect(response.body).to include("Walter Skinner", "Monica Reyes", "Comp")

    post manage_ticket_listing_comps_path(listing), params: { guests: "Too Many, 50", tier_id: general.id }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("more than the seats left", "Too Many, 50")
  end

  it "goes back where it came from after a status change" do
    post manage_ticket_listing_status_path(listing, status: "paused"), headers: { "HTTP_REFERER" => manage_ticket_listing_url(listing) }
    expect(response).to redirect_to(manage_ticket_listing_url(listing))
    expect(listing.reload.status).to eq("paused")
  end
end
