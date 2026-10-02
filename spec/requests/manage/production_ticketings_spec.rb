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
    expect(response.body).to include('value="General admission"', "Drag to reorder", "Move up")

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
                                     manage_ticket_listing_path(first_show.ticket_listing), tickets_production_path(org: TicketingProfile.for(org).slug, production: production.id))
    get manage_ticket_listings_path
    expect(response.body).to include("Rising Stars", "Selling", "2 upcoming dates")
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
          params: { production_ticketing: { capacity: "80", fee_mode: "org", title: "Rising Stars Showcase", door_note: "" } }
    setup = production.reload.production_ticketing
    expect(setup.attributes.slice("capacity", "fee_mode", "title", "door_note"))
      .to eq("capacity" => 80, "fee_mode" => "org", "title" => "Rising Stars Showcase", "door_note" => nil)

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
end
