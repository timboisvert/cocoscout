# frozen_string_literal: true

require "rails_helper"

# A production team's view of its ticket sales in the Production Dashboard
# (Manage::ProductionSalesController), by Who sees sales: a manager at
# Everything sees names and gives comps within the allowance; a viewer the
# numbers; nobody reaches /manage/ticketing from here.
RSpec.describe "Production sales for the production team", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19, min: 30)) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 3_000, quantity: 80) }
  let(:manager) { create(:user, email_address: "clay@sg.example", password: password) }
  let!(:manager_person) { create(:person, user: manager, name: "Clay Smith").tap { |p| manager.update!(default_person: p) } }
  let(:viewer) { create(:user, email_address: "priya@sg.example", password: password) }
  let(:profile) { TicketingProfile.for(org) }

  before do
    profile.update!(enabled: true, team_comps_limit: "fixed", team_comps_per_show: 2)
    create(:organization_role, :manager, user: owner, organization: org)
    [ [ manager, "manager" ], [ viewer, "viewer" ] ].each do |user, role|
      create(:organization_role, user: user, organization: org, company_role: "member")
      ProductionPermission.create!(user: user, production: production, role: role)
    end
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com", buyer_phone: "312-555-0100")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  it "shows a production team manager every date, one date with who's coming by name, and never an email or the module" do
    sign_in(manager)
    get manage_production_path(production)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-production-tickets-card", "Next up", "of 80</span> sold", manage_production_sales_path(production), manage_production_sale_path(production, listing))
    expect(response.body).not_to include(manage_ticketing_path)

    get manage_production_show_path(production, show)
    expect(response.body).to include("Tickets sold", manage_production_sale_path(production, listing), "See who&#39;s coming", "Give comps · 2 of 2 left")

    get manage_production_sales_path(production)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("How Stargazers is selling", "Upcoming", "Past", "/t/#{ShortLink.canonical_for!(production).code}", manage_production_sale_path(production, listing))
    expect(response.body).not_to include("/manage/ticketing", "Played")

    get manage_production_sale_path(production, listing)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Who's coming", "Dana Scully", "Sold here", "Your comps for this date", "0 of 2 given", 'id="comps-modal"',
                                     manage_production_sale_comps_path(production, listing))
    expect(response.body).not_to include("dana@example.com", "/manage/ticketing", "You keep")
  end

  it "lets the manager give comps within the allowance and refuses past it" do
    sign_in(manager)
    post manage_production_sale_comps_path(production, listing), params: { name: "Bea Thornton", quantity: "1", tier_id: general.id, email_them: "0" }
    expect(response).to redirect_to(manage_production_sale_path(production, listing, anchor: "guests"))
    expect(flash[:notice]).to eq("Gave 1 ticket to Bea Thornton. They're on the list.")
    expect(listing.ticket_orders.where(channel: "comp", issued_by: manager).count).to eq(1)

    get manage_production_sale_path(production, listing)
    expect(response.body).to include("1 of 2 given", "Give comps · 1 of 2 left", "You can give 1 more for this date.")

    post manage_production_sale_comps_path(production, listing), params: { name: "Too Many", quantity: "2", tier_id: general.id, email_them: "0" }
    expect(flash[:alert]).to eq("You can give 1 more comp for this date.")
    expect(listing.ticket_orders.where(channel: "comp").count).to eq(1)

    post manage_production_sale_comps_path(production, listing), params: { name: "Eli Park", quantity: "1", tier_id: general.id, email_them: "0" }
    post manage_production_sale_comps_path(production, listing), params: { name: "One Over", quantity: "1", tier_id: general.id, email_them: "0" }
    expect(flash[:alert]).to eq("You can't give comps for this date.")
    expect(listing.ticket_orders.where(channel: "comp").count).to eq(2)

    get manage_production_sale_path(production, listing)
    expect(response.body).to include("None left to give")
    expect(response.body).not_to include('id="comps-modal"')
  end

  it "says the money is so far while a site's amount isn't reported yet, so nobody reads it as under-reported" do
    tailor = org.ticket_sources.create!(name: "Ticket Tailor")
    hottix = org.ticket_sources.create!(name: "HotTix")
    TicketOutsideSales.record!(listing, { tailor.id.to_s => { general.id.to_s => { "tickets" => "7", "amount" => "$210" } },
                                          hottix.id.to_s => { general.id.to_s => { "tickets" => "3", "amount" => "" } } })
    sign_in(manager)
    get manage_production_show_path(production, show)
    expect(response.body).to include("$270.00 in sales so far", "3 on HotTix", "not reported yet")
    get manage_production_sale_path(production, listing)
    expect(response.body).to include("$210.00 so far", "$210 on Ticket Tailor; HotTix not reported yet")
    expect(response.body).not_to include("Add the amounts")
    get manage_production_sales_path(production)
    expect(response.body).to include("$270 so far")
  end

  it "shows a production team viewer the numbers and the link, with no names, money or comps" do
    sign_in(viewer)
    get manage_production_path(production)
    expect(response.body).to include("data-production-tickets-card", "Next up")
    expect(response.body).not_to include(manage_production_sales_path(production), manage_production_sale_path(production, listing))

    get manage_production_show_path(production, show)
    expect(response.body).to include("Tickets sold", manage_production_sale_path(production, listing))
    expect(response.body).not_to include("See who", "Give comps", "in sales")

    get manage_production_sale_path(production, listing)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tickets sold", "2 of 80 sold", "/t/#{ShortLink.canonical_for!(production).code}")
    expect(response.body).not_to include("Who's coming", "Dana Scully", "$", "comps-modal", "Sold here")
  end

  it "keeps everyone else out: Nothing, a free organization, a closed box office, another production's date, an organization manager" do
    sign_in(manager)
    other = create(:production, organization: org, name: "Other")
    other_listing = create(:ticket_listing, organization: org, show: create(:show, production: other))
    get manage_production_sale_path(production, other_listing)
    expect(response).to have_http_status(:not_found)

    profile.update!(team_manager_sales: "nothing")
    get manage_production_sales_path(production)
    expect(response).to redirect_to(manage_production_path(production))
    get manage_production_path(production)
    expect(response.body).not_to include("data-production-tickets-card")
    get manage_production_show_path(production, show)
    expect(response.body).not_to include("Tickets sold")
    profile.update!(team_manager_sales: "everything")

    profile.update!(enabled: false)
    get manage_production_sales_path(production)
    expect(response).to redirect_to(manage_production_path(production))
    profile.update!(enabled: true)

    org.update!(comped_indefinitely: false)
    get manage_production_sales_path(production)
    expect(response).to redirect_to(manage_production_path(production))
    org.update!(comped_indefinitely: true)

    sign_in(owner)
    get manage_production_sales_path(production)
    expect(response).to redirect_to(manage_production_ticketing_path(production))
  end

  it "leaves the Visibility page knowing the team already sees it, and offers no share to them" do
    sign_in(owner)
    get manage_production_ticketing_visibility_path(production)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("production team already sees these sales by role", "its managers everything, its viewers the numbers, and the cast the count and the link",
                                     manage_ticketing_settings_section_path(section: "sharing"))
    expect(response.body).not_to include("Clay Smith")
  end
end
