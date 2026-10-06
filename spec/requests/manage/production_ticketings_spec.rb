# frozen_string_literal: true

require "rails_helper"

# Setting ticketing up once for a repeating production, sign-ups style: which
# dates (all performances, some event types, or picked by hand), when sales
# open and close, and the ticket prices for every date — then the
# production's page lists each date and how it's selling.
RSpec.describe "Production ticketing", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let!(:first_show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let!(:second_show) { create(:show, production: production, date_and_time: 19.days.from_now.change(hour: 19, min: 30)) }
  let!(:rehearsal) { create(:show, :rehearsal, production: production, date_and_time: 4.days.from_now) }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  # Tim (2026-10-06): a listed date is for sale; "N days before" is the alternative.
  it "sells each date right away by default" do
    setup = ProductionTicketing.for(production)
    expect([ setup.schedule_mode, setup.opens_days_before ]).to eq([ "immediate", 30 ])
    get manage_edit_production_ticketing_path(production, section: "dates")
    expect(response.body.index("Right away, as soon as a date is listed")).to be < response.body.index("days before each date")
  end

  def save_tickets(rows)
    patch manage_update_production_ticketing_path(production, section: "tickets"),
          params: { production_ticketing: { ticket_tiers_attributes: rows } }
  end

  def save_dates(**attrs)
    patch manage_update_production_ticketing_path(production, section: "dates"),
          params: { production_ticketing: { enabled: "1", event_matching: "all", schedule_mode: "relative",
                                            opens_days_before: "30", online_close_minutes: "0" }.merge(attrs.except(:selected_show_ids)),
                    selected_show_ids: attrs[:selected_show_ids] }
  end

  it "goes straight to the production when there's only one, and asks which when there are several" do
    get manage_new_production_ticketing_path
    expect(response).to redirect_to(manage_production_ticketing_path(production))

    create(:production, organization: org, name: "The Late Show")
    get manage_new_production_ticketing_path
    expect(response.body).to include("Which production?")
  end

  it "sets it up: prices once, then which dates, and every matching date goes on sale" do
    get manage_production_ticketing_path(production)
    expect(response.body).to include("Not set up", "Sell tickets for every date of Rising Stars", "Set it up")

    get manage_edit_production_ticketing_path(production, section: "tickets")
    expect(response.body).to include('value="General admission"', "Drag to reorder", "Move up", "Add a ticket type", "Add a bundle")
    # A plain ticket type never asks how many it admits; only a bundle row does.
    plain = response.body.split('data-nested-form-target="template"').first
    expect(plain).not_to include("People the bundle admits")

    save_tickets("0" => { name: "General", price: "20", quantity: "60", position: "1" },
                 "1" => { name: "Student", price: "$15.00", quantity: "", position: "0" },
                 "2" => { name: "", price: "", quantity: "", position: "2" })
    setup = production.reload.production_ticketing
    expect(setup.ticket_tiers.map { |t| [ t.name, t.price_cents, t.quantity ] }).to eq([ [ "Student", 1_500, nil ], [ "General", 2_000, 60 ] ])
    expect(setup.enabled).to be(false)

    get manage_edit_production_ticketing_path(production, section: "dates")
    expect(response.body).to include("Which dates?", "All performances", "By event type", "Specific dates", "When sales open and close")

    save_dates
    expect(flash[:notice]).to eq("Saved. 2 dates added.")
    expect([ first_show, second_show ].map { |s| s.reload.ticket_listing&.inherits_tiers }).to eq([ true, true ])
    expect(rehearsal.reload.ticket_listing).to be_nil
    expect(first_show.ticket_listing.on_sale_at).to eq(first_show.date_and_time - 30.days)

    get manage_production_ticketing_path(production)
    expect(response.body).to include("Selling", "All performances", "New dates join on their own",
                                     manage_ticket_listing_path(first_show.ticket_listing), "/t/#{production.reload.short_link.code}")
    get manage_ticket_listings_path
    expect(response.body).to include("Rising Stars", "Selling", "2 upcoming dates")
  end

  it "pauses every date when switched off, and resumes them when switched on" do
    save_tickets("0" => { name: "General", price: "20", position: "0" })
    save_dates
    expect(first_show.reload.ticket_listing.status).to eq("on_sale")

    save_dates(enabled: "0")
    expect(flash[:notice]).to start_with("Off.")
    expect([ first_show.reload.ticket_listing.status, second_show.reload.ticket_listing.status ]).to eq(%w[paused paused])
    get manage_production_ticketing_path(production)
    expect(response.body).to include(">Off<", "Turn it on", "Paused")

    save_dates(enabled: "1")
    expect(first_show.reload.ticket_listing.status).to eq("on_sale")
  end

  it "takes dates picked by hand, and drops a date nobody bought when it's unpicked" do
    save_tickets("0" => { name: "General", price: "20", position: "0" })
    save_dates(event_matching: "manual", selected_show_ids: [ first_show.id, second_show.id ])
    expect(production.reload.production_ticketing.selected_shows).to contain_exactly(first_show, second_show)

    save_dates(event_matching: "manual", selected_show_ids: [ "", first_show.id.to_s ])
    expect(flash[:notice]).to eq("Saved. 1 removed.")
    expect(second_show.reload.ticket_listing).to be_nil

    get manage_production_ticketing_path(production)
    expect(response.body).to include("Dates picked by hand")
    expect(response.body).not_to include("New dates join on their own")
  end

  it "saves seats, fees and words for every date, and production-wide codes" do
    patch manage_update_production_ticketing_path(production, section: "sales"),
          params: { production_ticketing: { max_per_order: "6", fee_mode: "org", title: "Rising Stars Showcase", door_note: "" } }
    setup = production.reload.production_ticketing
    expect(setup.attributes.slice("max_per_order", "fee_mode", "title", "door_note"))
      .to eq("max_per_order" => 6, "fee_mode" => "org", "title" => "Rising Stars Showcase", "door_note" => nil)

    post manage_production_ticketing_codes_path(production), params: { ticket_discount_code: { code: "friends", kind: "fixed", amount: "5" } }
    code = org.ticket_discount_codes.sole
    expect([ code.code, code.production_id, code.amount_cents ]).to eq([ "FRIENDS", production.id, 500 ])
    get manage_edit_production_ticketing_path(production, section: "codes")
    expect(response.body).to include("FRIENDS", "$5.00 off")

    delete manage_production_ticketing_code_path(production, code_id: code.id)
    expect(code.reload.active).to be(false)
  end

  it "can't reach another theater's production" do
    other = create(:production, organization: create(:organization, :pro))
    get manage_production_ticketing_path(other)
    expect(response).to have_http_status(:not_found)
    patch manage_update_production_ticketing_path(other, section: "dates"), params: { production_ticketing: { enabled: "1" } }
    expect(response).to have_http_status(:not_found)
    expect(ProductionTicketing.where(production: other)).to be_empty
  end

  # Tim (2026-10-02): a date's Settings work like the production's, with a
  # bar saying it's this date only; the date sits under its production.
  describe "one date's settings" do
    before do
      save_tickets("0" => { name: "General", price: "20", quantity: "60", position: "0" })
      save_dates
    end

    let(:listing) { first_show.reload.ticket_listing }

    it "says it's this date only, shows the production's prices, and can give the date its own" do
      get manage_ticket_listing_path(listing)
      expect(response.body).to include(manage_production_ticketing_path(production), ">Rising Stars<")

      get manage_edit_ticket_listing_path(listing)
      expect(response.body).to include("Settings for #{listing.show.date_and_time.strftime('%a, %b %-d')}", "only.",
                                       "uses Rising Stars&#39; ticketing", "Set tickets and prices for this date only",
                                       "<fieldset disabled", 'value="General"', "Discount codes")

      # The switch on, with a price of this date's own.
      copy = listing.ticket_tiers.sole
      patch manage_ticket_listing_path(listing), params: { section: "tickets", ticket_listing: {
        own_prices: "1", ticket_tiers_attributes: { "0" => { id: copy.id, name: "General", price: "18", quantity: "60", position: "0" } }
      } }
      expect(listing.reload.inherits_tiers).to be(false)
      expect(listing.ticket_tiers.active.sole.attributes.slice("price_cents", "source_tier_id")).to eq("price_cents" => 1_800, "source_tier_id" => nil)
      get manage_edit_ticket_listing_path(listing, section: "tickets")
      expect(response.body).to include("Add a ticket type")
      expect(response.body).not_to include("<fieldset disabled")

      setup = ProductionTicketing.find_by!(production: production)
      setup.ticket_tiers.sole.update!(price_cents: 2_500)
      ProductionTicketingSync.sync_all!(setup)
      expect(listing.ticket_tiers.active.sole.price_cents).to eq(1_800)

      # The switch off again: back to the production's, the unsold own type gone.
      patch manage_ticket_listing_path(listing), params: { section: "tickets", ticket_listing: { own_prices: "0" } }
      expect(listing.reload.inherits_tiers).to be(true)
      expect(listing.ticket_tiers.map(&:price_cents)).to eq([ 2_500 ])
    end

    it "keeps each tab's form to itself" do
      get manage_edit_ticket_listing_path(listing, section: "sales")
      expect(response.body).to include("When sales open and close", "Who pays the fees")
      get manage_edit_ticket_listing_path(listing, section: "codes")
      expect(response.body).to include("good for this date")
    end
  end
end
