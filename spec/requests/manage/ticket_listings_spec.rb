# frozen_string_literal: true

require "rails_helper"

# Running each date: prices and seats, the sales window, the fee switch,
# codes. (Setting a production's dates up at once: production_ticketings_spec.)
RSpec.describe "Manage ticket listings", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs") }
  let!(:friday) { create(:show, production: production, date_and_time: 3.days.from_now.change(hour: 19, min: 30)) }
  let!(:saturday) { create(:show, production: production, date_and_time: 4.days.from_now.change(hour: 19, min: 30)) }
  let!(:rehearsal) { create(:show, :rehearsal, production: production, date_and_time: 2.days.from_now) }

  before do
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  describe "running a date" do
    let!(:listing) { TicketListing.create!(show: friday) }
    let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

    it "lists its production on Shows, and the date on the production's page, draft then on sale" do
      get manage_ticket_listings_path
      expect(response.body).to include("Improvised Animorphs", manage_production_ticketing_path(production), "1 upcoming date")

      get manage_production_ticketing_path(production)
      expect(response.body).to include(manage_ticket_listing_path(listing), "Draft", "Not set up")

      post manage_ticket_listing_status_path(listing), params: { status: "on_sale" }
      expect(listing.reload.status).to eq("on_sale")
      get manage_production_ticketing_path(production)
      expect(response.body).to include("On sale").and include("of 60")
    end

    it "pauses, resumes and closes, but never jumps a step that doesn't exist" do
      post manage_ticket_listing_status_path(listing), params: { status: "paused" }
      expect(flash[:alert]).to be_present
      expect(listing.reload.status).to eq("draft")

      listing.update!(status: "on_sale")
      post manage_ticket_listing_status_path(listing), params: { status: "paused" }
      post manage_ticket_listing_status_path(listing), params: { status: "closed" }
      expect(listing.reload.status).to eq("closed")
    end

    it "edits prices in place: changes, additions, and removing an unsold one" do
      vip = listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500)
      patch manage_ticket_listing_path(listing), params: { ticket_listing: {
        fee_mode: "org",
        ticket_tiers_attributes: {
          "0" => { id: general.id, name: "General", price: "22.50", quantity: "50" },
          "1" => { id: vip.id, name: "VIP", price: "35", quantity: "", _destroy: "1" },
          "2" => { name: "Student", price: "12", quantity: "10" },
          "3" => { name: "", price: "", quantity: "" }
        }
      } }

      expect(response).to redirect_to(manage_edit_ticket_listing_path(listing, section: "tickets"))
      expect(listing.reload.effective_fee_mode).to eq("org")
      expect(listing.ticket_tiers.active.map { |t| [ t.name, t.price_cents, t.quantity ] })
        .to eq([ [ "General", 2_250, 50 ], [ "Student", 1_200, 10 ] ])
      expect(TicketTier.exists?(vip.id)).to be(false)
    end

    it "keeps a sold price for its buyers when it's removed, and won't cut seats below what's sold" do
      order = create(:ticket_order, ticket_listing: listing, status: "paid")
      2.times { create(:ticket, ticket_order: order, ticket_tier: general) }

      patch manage_ticket_listing_path(listing), params: { ticket_listing: { ticket_tiers_attributes: {
        "0" => { id: general.id, name: "General", price: "20", quantity: "1" }
      } } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("fewer than the 2 already sold")

      patch manage_ticket_listing_path(listing), params: { ticket_listing: { ticket_tiers_attributes: {
        "0" => { id: general.id, name: "General", price: "20", quantity: "60", _destroy: "1" }
      } } }
      expect(general.reload.archived_at).to be_present
    end

    it "takes discount codes, and switches off a used one rather than deleting it" do
      post manage_ticket_listing_codes_path(listing), params: { ticket_discount_code: { code: "friends", kind: "fixed", amount: "5" } }
      code = listing.ticket_discount_codes.sole
      expect([ code.code, code.amount_cents ]).to eq([ "FRIENDS", 500 ])

      create(:ticket_order, ticket_listing: listing, ticket_discount_code: code, status: "paid")
      delete manage_ticket_listing_code_path(listing, code_id: code.id)
      expect(code.reload.active).to be(false)
    end

    it "removes a draft nobody has bought, but not one with orders" do
      delete manage_ticket_listing_path(listing)
      expect(TicketListing.exists?(listing.id)).to be(false)
      expect(friday.reload).to be_present

      other = TicketListing.create!(show: saturday, status: "on_sale")
      create(:ticket_order, ticket_listing: other)
      delete manage_ticket_listing_path(other)
      expect(TicketListing.exists?(other.id)).to be(true)
    end

    it "never reaches another organization's listing" do
      theirs = create(:ticket_listing)
      get manage_edit_ticket_listing_path(theirs)
      expect(response).to have_http_status(:not_found)
    end
  end
end
