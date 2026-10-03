# frozen_string_literal: true

require "rails_helper"

# Products sold with tickets: the org's list with standard prices, and a
# production choosing which to upsell, at its own prices when it says so.
RSpec.describe "Ticket products", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  it "adds, edits and removes products, and the dashboard points at them" do
    get manage_ticketing_path
    expect(response.body).to include("Products", manage_ticket_products_path)

    get manage_ticket_products_path
    expect(response.body).to include("No products yet")

    post manage_ticket_products_path, params: { ticket_product: { name: "Champagne bottle", price: "$45", description: "Bubbly at your table",
                                                                   counts_toward_ticket_revenue: "0", taxable: "1" } }
    product = org.ticket_products.find_by!(name: "Champagne bottle")
    expect([ product.price_cents, product.description, product.counts_toward_ticket_revenue, product.taxable ]).to eq([ 4_500, "Bubbly at your table", false, true ])

    get manage_ticket_products_path
    expect(response.body).to include("Champagne bottle", "$45.00", "Not offered on any production yet")

    patch manage_ticket_product_path(product), params: { ticket_product: { name: "Champagne", price: "50", counts_toward_ticket_revenue: "1", taxable: "0" } }
    expect(product.reload.attributes.values_at("name", "price_cents", "counts_toward_ticket_revenue", "taxable")).to eq([ "Champagne", 5_000, true, false ])

    post manage_ticket_products_path, params: { ticket_product: { name: "", price: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    delete manage_ticket_product_path(product)
    expect(TicketProduct.exists?(product.id)).to be(false)
  end

  it "never reaches another organization's product" do
    other = create(:ticket_product, organization: create(:organization, :pro))
    get manage_edit_ticket_product_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it "lets a production pick which products to upsell, at its own prices when the switch is on" do
    bottle = create(:ticket_product, organization: org, name: "Champagne bottle", price_cents: 4_500)
    program = create(:ticket_product, organization: org, name: "Program", price_cents: 500, counts_toward_ticket_revenue: true)
    setup = ProductionTicketing.for(production)

    get manage_edit_production_ticketing_path(production, section: "products")
    expect(response.body).to include("can add these at checkout", "Set prices for this production only", "Sell them at the door too", "Champagne bottle", "Program")

    # Standard prices: the switch is off, so typed prices are ignored.
    patch manage_update_production_ticketing_path(production, section: "products"),
          params: { production_ticketing: { own_product_prices: "0" },
                    products: { bottle.id.to_s => { offered: "1", price: "99" }, program.id.to_s => { offered: "0" } } }
    expect(response).to redirect_to(manage_edit_production_ticketing_path(production, section: "products"))
    offers = setup.reload.product_offers
    expect(offers.map { |o| [ o.name, o.price_cents, o.counts_toward_ticket_revenue ] }).to eq([ [ "Champagne bottle", 4_500, false ] ])

    # The production's own prices and revenue rule.
    patch manage_update_production_ticketing_path(production, section: "products"),
          params: { production_ticketing: { own_product_prices: "1", products_at_door: "1" },
                    products: { bottle.id.to_s => { offered: "1", price: "$60.00", counts_toward_ticket_revenue: "1" },
                                program.id.to_s => { offered: "1", price: "", counts_toward_ticket_revenue: "0" } } }
    expect(setup.reload.products_at_door).to be(true)
    offers = setup.product_offers
    expect(offers.map { |o| [ o.name, o.price_cents, o.counts_toward_ticket_revenue ] })
      .to eq([ [ "Champagne bottle", 6_000, true ], [ "Program", 500, false ] ])

    # Switching the production's own prices off goes back to the products'.
    patch manage_update_production_ticketing_path(production, section: "products"),
          params: { production_ticketing: { own_product_prices: "0" },
                    products: { bottle.id.to_s => { offered: "1" }, program.id.to_s => { offered: "1" } } }
    expect(setup.reload.product_offers.map { |o| [ o.price_cents, o.counts_toward_ticket_revenue ] }).to eq([ [ 4_500, false ], [ 500, true ] ])

    # The production's page points at the tab, naming what's offered.
    get manage_production_ticketing_path(production)
    expect(response.body).to include("Champagne bottle and Program", manage_edit_production_ticketing_path(production, section: "products"))

    # A date of the production offers what the production does; a removed
    # product that was never bought simply goes.
    show = create(:show, production: production, date_and_time: 5.days.from_now)
    listing = create(:ticket_listing, organization: org, show: show)
    expect(listing.product_offers.map(&:name)).to eq([ "Champagne bottle", "Program" ])
    delete manage_ticket_product_path(program)
    expect(listing.reload.product_offers.map(&:name)).to eq([ "Champagne bottle" ])
  end
end
