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

  it "lists every production in a slim line: its next date, the next few in a drawer, then those with none coming" do
    dates = (1..8).map do |n|
      TicketListing.create!(show: create(:show, production: production, date_and_time: (n * 3).days.from_now.change(hour: 20)), status: "on_sale")
    end
    quiet = create(:production, organization: org, name: "Last Season")
    ProductionTicketing.for(quiet)

    get manage_ticket_listings_path
    body = response.body
    expect(body).to include("8 dates", "7 more dates", "All 8 dates of Improvised Animorphs",
                            manage_ticket_listing_path(dates.first), manage_ticket_listing_path(dates[5]), "No dates coming up", "Last Season")
    expect(body).not_to include(manage_ticket_listing_path(dates[6]), "this week")
    expect(body.index("Improvised Animorphs")).to be < body.index("Last Season")
  end

  describe "running a date" do
    let!(:listing) { TicketListing.create!(show: friday) }
    let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

    it "says a title of its own on its page, and only one of its own" do
      get manage_ticket_listing_path(listing)
      expect(response.body).not_to include("This date's own title")

      listing.update!(title: "Twilight: Breaking Dawn Part 2")
      get manage_ticket_listing_path(listing)
      expect(response.body).to include("This date's own title", "Twilight: Breaking Dawn Part 2",
                                       manage_edit_ticket_listing_path(listing, section: "page"))

      # The suggested show name, or the production's own, isn't a title of its own.
      listing.update!(title: nil)
      friday.update!(secondary_name: friday.suggested_name)
      expect(TicketListing.find(listing.id).own_title).to be_nil
      friday.update!(secondary_name: "Opening Night")
      expect(TicketListing.find(listing.id).own_title).to eq("Opening Night")
      listing.update!(title: "Improvised Animorphs")
      expect(TicketListing.find(listing.id).own_title).to be_nil
    end

    it "lists its production on Shows, and the date on the production's page, draft then on sale" do
      get manage_ticket_listings_path
      expect(response.body).to include("Improvised Animorphs", manage_production_ticketing_path(production), "1 date")

      get manage_production_ticketing_path(production)
      expect(response.body).to include(manage_ticket_listing_path(listing), "Draft", "Not set up")

      post manage_ticket_listing_status_path(listing), params: { status: "on_sale" }
      expect(listing.reload.status).to eq("on_sale")
      get manage_production_ticketing_path(production)
      expect(response.body).to include("On sale").and include("of 60")
    end

    it "records tickets sold on other sites by ticket type, takes those seats here, and says why" do
      listing.update!(status: "on_sale")
      vip = listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500, quantity: 10)
      eventbrite = org.ticket_sources.create!(name: "Eventbrite")

      get manage_ticket_listing_path(listing)
      expect(response.body).to include("Sold elsewhere", 'id="outside-sales-modal"', 'id="comps-modal"', "Eventbrite")
      expect(response.body).not_to include("Give tickets</div>")

      patch manage_ticket_listing_outside_sales_path(listing), params: {
        new_source_name: "Ticket Tailor",
        sales: { eventbrite.id.to_s => { general.id.to_s => { tickets: "4", amount: "$80" } },
                 "new" => { vip.id.to_s => { tickets: "6", amount: "" } } }
      }
      expect(response).to redirect_to(manage_ticket_listing_path(listing))
      expect(flash[:notice]).to eq("10 tickets sold elsewhere, off this show's seats.")

      tailor = org.ticket_sources.find_by!(name: "Ticket Tailor")
      lines = friday.show_financials.ticket_sales_lines.index_by(&:ticket_source_id)
      expect(lines[eventbrite.id].attributes.values_at("tickets_sold", "amount")).to eq([ 4, 80.to_d ])
      expect(lines[tailor.id].attributes.values_at("tickets_sold", "amount")).to eq([ 6, 0.to_d ])
      expect([ listing.inventory.remaining(tier: general), listing.inventory.remaining(tier: vip) ]).to eq([ 56, 4 ])

      get manage_ticket_listing_path(listing)
      # Sold counts every ticket sold, here or elsewhere, and says where.
      # Here and elsewhere, each with its money; the whole picture under Sold here.
      expect(response.body).to include("6 on Ticket Tailor", "4 on Eventbrite", "Sold here", "10 of 70 sold in all", "Add a ticket type", 'data-tier-chip="')
      expect(response.body).to include("Ticket sales elsewhere", "$80.00", "$80 on Eventbrite", "$0 here")
      expect(response.body).not_to include("$0 on Ticket Tailor")
      # Only the rows a site has are drawn; the rest come from the template on Add.
      expect(response.body.scan(/name="sales\[#{eventbrite.id}\]\[\d+\]\[tickets\]"/).size).to eq(1)

      # The worksheet shows those rows but doesn't let anyone type over them,
      # and links back to the ticketing page where they're changed.
      get manage_money_show_financials_path(friday)
      expect(response.body).to match(%r{<a [^>]*href="#{manage_ticket_listing_path(listing)}"[^>]*>imported from the ticketing page</a>})
      expect(response.body).not_to match(/ticket_sales_lines_attributes\]\[\d+\]\[ticket_source_id\]"[^>]*value="#{eventbrite.id}"/)
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
