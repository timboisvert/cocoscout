# frozen_string_literal: true

require "rails_helper"

# Products on the pages people see: the checkout's "Add to your order",
# the buyer's order page, the manager's order page, the guest list and the
# door — and a date that offers none shows none.
RSpec.describe "Ticket products on pages", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:show) { create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 19, min: 30)) }
  let(:bottle) { create(:ticket_product, organization: org, name: "Champagne bottle", price_cents: 4_500, description: "Bubbly at your table") }
  # The production's setup comes first: a listing reads it when it's made.
  let!(:setup) do
    TicketingProfile.for(org).update!(enabled: true)
    ProductionTicketing.for(production).tap { |s| s.production_ticketing_products.create!(ticket_product: bottle, position: 0) }
  end
  let(:listing) { create(:ticket_listing, organization: org, show: show, slug: "rising-stars") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  def sign_in_manager
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  it "offers the production's products at checkout and saves what the buyer adds" do
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    get tickets_checkout_path(token: order.token)
    expect(response.body).to include("Add to your order", "Champagne bottle", "Bubbly at your table", "Waiting for you at the show", "$45.00")
    expect(response.body).not_to include("incl. fees")

    patch tickets_checkout_items_path(token: order.token), params: { products: { bottle.id.to_s => "2" } }, as: :json
    data = response.parsed_body
    expect(data["items"]).to eq({ bottle.id.to_s => 2 })
    expect(data["summary_html"]).to include("2 × Champagne bottle", "$90.00")
    expect(data["total_cents"]).to eq(order.reload.total_cents)

    # Another date, with no production products, offers none.
    lone = create(:ticket_listing, organization: org, slug: "lone")
    lone_tier = lone.ticket_tiers.create!(name: "General", price_cents: 2_000)
    lone_order = TicketCheckout.start!(listing: lone, quantities: { lone_tier.id.to_s => "1" })
    get tickets_checkout_path(token: lone_order.token)
    expect(response.body).not_to include("Add to your order")
  end

  it "shows what was bought everywhere the order appears" do
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    TicketCheckout.set_items!(order, { bottle.id.to_s => "1" })
    order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")

    get tickets_order_path(token: order.token)
    expect(response.body).to include("Also with this order", "1 × Champagne bottle")

    mail = TicketOrderMailer.confirmation(order.reload)
    expect(mail.html_part.body.to_s).to include("Also with this order", "1 × Champagne bottle")

    sign_in_manager
    get manage_ticket_order_path(order.id)
    expect(response.body).to include("Products", "1 × Champagne bottle", "Not delivered yet", "Tickets", "$40.00", "$45.00")

    get manage_ticket_listing_path(listing)
    expect(response.body).to include("1 × Champagne bottle", "Products", "Delivered")

    get manage_ticket_listing_guests_path(listing, format: :csv)
    expect(response.body).to include("Products", "1 × Champagne bottle")

    get manage_ticket_listing_door_list_path(listing)
    expect(response.body).to include("<th>Products</th>", "1 × Champagne bottle")

    # The door: the bottle on the order, and one tap to hand it over.
    get door_search_path(listing, q: "Avery")
    expect(response.body).to include("1 × Champagne bottle", "Delivered")
    item = order.ticket_order_items.sole
    # A scan at the door names what they pre-bought, with a hand-over tap.
    post door_check_in_path(listing), params: { code: order.tickets.first.code }, as: :json
    scan = response.parsed_body
    expect(scan["party"]).to eq("1 of 2 in")
    expect(scan["items"]).to eq([ { "id" => item.id, "label" => "1 × Champagne bottle", "fulfilled" => false, "fulfill_url" => door_fulfill_path(listing, item_id: item.id) } ])
    post door_fulfill_path(listing, item_id: item.id), as: :json
    expect(response.parsed_body["message"]).to eq("1 × Champagne bottle delivered")
    expect(item.reload.fulfilled?).to be(true)

    # The door sells products only once the production turns that on.
    get door_path(listing)
    expect(response.body).not_to include("With it")
    # The bottle was delivered above; the To-deliver list says so.
    expect(response.body).to include("To deliver", "0 of 1 left", "Everything's delivered")
    get door_deliveries_path(listing)
    expect(response.body).to include("Everything's delivered")
    setup.update!(products_at_door: true)
    get door_path(listing)
    expect(response.body).to include("With it", "Champagne bottle")

    # A date can switch the production's products off for itself.
    get manage_edit_ticket_listing_path(listing, section: "products")
    expect(response.body).to include("Sell products for this date", "Champagne bottle")
    patch manage_ticket_listing_path(listing), params: { section: "products", ticket_listing: { sell_products: "0" } }
    expect(listing.reload.sell_products).to be(false)
    get door_path(listing)
    expect(response.body).not_to include("With it")
    listing.update!(sell_products: true)

    # Refunding only the bottle from the order page.
    allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_1"))
    get manage_ticket_order_refund_path(order.id, ticket_ids: [ "" ], item_ids: [ item.id ])
    expect(response.body).to include("Refund $", "1 × Champagne bottle")
    post manage_ticket_order_refund_path(order.id), params: { ticket_ids: [ "" ], item_ids: [ item.id ], keep_fees: "0" }
    expect(order.reload.status).to eq("partially_refunded")
    expect(order.tickets.pluck(:status)).to contain_exactly("checked_in", "valid")
  end
end
