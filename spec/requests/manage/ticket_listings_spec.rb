# frozen_string_literal: true

require "rails_helper"

# Shows on sale: putting a production's dates on sale in one go, then running
# each date — prices and seats, the sales window, the fee switch, codes.
# Nothing goes on sale by itself.
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

  def put_on_sale(shows, opening: "draft", tiers: { "0" => { name: "General", price: "20", quantity: "60" } }, **extra)
    post manage_ticket_listings_path, params: { production_id: production.id, show_ids: shows.map(&:id), tiers: tiers, opening: opening, **extra }
  end

  describe "putting a production's dates on sale" do
    it "goes straight to the dates when the org has one production, and offers only ticketed shows" do
      get manage_new_ticket_listing_path
      expect(response).to redirect_to(manage_new_ticket_listing_path(production_id: production.id))

      follow_redirect!
      expect(response.body).to include(%(value="#{friday.id}")).and include(%(value="#{saturday.id}"))
      expect(response.body).not_to include(%(value="#{rehearsal.id}"))
    end

    it "asks which production when there are several" do
      create(:production, organization: org, name: "The Late Show")
      get manage_new_ticket_listing_path
      expect(response.body).to include("Which production?")
    end

    it "makes drafts by default, each date with the same prices" do
      put_on_sale([ friday, saturday ], tiers: { "0" => { name: "General", price: "$20.00", quantity: "60" },
                                                "1" => { name: "VIP", price: "35", quantity: "" },
                                                "2" => { name: "", price: "", quantity: "" } })

      expect(response).to redirect_to(manage_ticket_listings_path(filter: "drafts"))
      listings = org.ticket_listings.order(:id)
      expect(listings.map(&:status)).to eq(%w[draft draft])
      expect(listings.first.ticket_tiers.map { |t| [ t.name, t.price_cents, t.quantity ] })
        .to eq([ [ "General", 2_000, 60 ], [ "VIP", 3_500, nil ] ])
    end

    it "puts them on sale now, or schedules the opening, when asked" do
      put_on_sale([ friday ], opening: "now")
      expect(friday.reload.ticket_listing.status).to eq("on_sale")

      put_on_sale([ saturday ], opening: "scheduled", on_sale_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M"))
      listing = saturday.reload.ticket_listing
      expect([ listing.status, listing.on_sale_at.to_date ]).to eq([ "on_sale", 1.day.from_now.to_date ])
    end

    it "leaves dates that already have tickets alone" do
      put_on_sale([ friday ])
      put_on_sale([ friday, saturday ])
      expect(org.ticket_listings.count).to eq(2)
      expect(flash[:notice]).to include("1 already had tickets and were left alone")
    end

    it "explains a price that isn't a number" do
      put_on_sale([ friday ], tiers: { "0" => { name: "General", price: "twenty", quantity: "" } })
      expect(flash[:alert]).to include("Check the ticket prices")
      expect(org.ticket_listings).to be_empty
    end
  end

  describe "running a date" do
    let!(:listing) { TicketListing.create!(show: friday) }
    let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

    it "lists it under drafts, then upcoming once it's on sale" do
      get manage_ticket_listings_path(filter: "drafts")
      expect(response.body).to include(manage_edit_ticket_listing_path(listing)).and include("Draft")

      post manage_ticket_listing_status_path(listing), params: { status: "on_sale" }
      expect(listing.reload.status).to eq("on_sale")
      get manage_ticket_listings_path
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

      expect(response).to redirect_to(manage_edit_ticket_listing_path(listing))
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
      expect(response).to have_http_status(:unprocessable_entity)
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
