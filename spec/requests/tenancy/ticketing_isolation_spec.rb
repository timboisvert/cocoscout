# frozen_string_literal: true

require "rails_helper"

# Ticketing on the manage side: every listing, order, refund and door grant is
# found through the current organization, so another theater's ids reach
# nothing. (Ticketing is superadmin-only while it's experimental; the scoping
# must hold anyway, for the day it opens up — and a superadmin working in one
# org must not act on another by pasting an id.)
RSpec.describe "Cross-org isolation (ticketing)", type: :request do
  let(:password) { "Password123!" }
  let(:attacker) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let!(:org) { create(:organization, :pro, owner: attacker) }

  let(:victim_org) { create(:organization, :pro) }
  let(:victim_listing) { create(:ticket_listing, organization: victim_org) }
  let!(:victim_tier) { victim_listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }
  let!(:victim_order) do
    order = TicketCheckout.start!(listing: victim_listing, quantities: { victim_tier.id.to_s => "1" })
    TicketOrderSettlement.settle!(order)
    order.reload
  end

  before do
    create(:organization_role, :manager, user: attacker, organization: org)
    post handle_signin_path, params: { email_address: attacker.email_address, password: password }
    get manage_path
    allow(Stripe::Refund).to receive(:create)
  end

  it "can't see, change, cancel or remove another theater's show" do
    get manage_edit_ticket_listing_path(victim_listing)
    expect(response).to have_http_status(:not_found)
    get manage_ticket_listing_path(victim_listing)
    expect(response).to have_http_status(:not_found)
    get manage_ticket_listing_guests_path(victim_listing, format: :csv)
    expect(response).to have_http_status(:not_found)
    get manage_ticket_listing_door_list_path(victim_listing)
    expect(response).to have_http_status(:not_found)
    get manage_ticket_listing_visibility_path(victim_listing)
    expect(response).to have_http_status(:not_found)
    get manage_production_ticketing_links_path(victim_listing.production)
    expect(response).to have_http_status(:not_found)
    post manage_production_ticketing_links_path(victim_listing.production), params: { label: "Poster" }
    expect(response).to have_http_status(:not_found)
    expect(ShortLink.named.count).to eq(0)
    post manage_ticket_listing_visibility_path(victim_listing), params: { person_id: create(:person, user: create(:user)).id, share_scope: "listing" }
    expect(response).to have_http_status(:not_found)
    expect(TicketSalesViewer.count).to eq(0)
    post manage_ticket_listing_comps_path(victim_listing), params: { name: "Me", quantity: "2", tier_id: victim_tier.id }
    expect(response).to have_http_status(:not_found)
    expect(victim_listing.ticket_orders.where(channel: "comp")).to be_empty

    patch manage_ticket_listing_path(victim_listing), params: { ticket_listing: { title: "Mine now" } }
    expect(response).to have_http_status(:not_found)
    post manage_ticket_listing_status_path(victim_listing), params: { status: "paused" }
    expect(response).to have_http_status(:not_found)
    post manage_ticket_listing_cancel_path(victim_listing), params: { subject: "x", body: "y" }
    expect(response).to have_http_status(:not_found)
    post manage_ticket_listing_codes_path(victim_listing), params: { code: { code: "FREE", kind: "percent", amount: "100" } }
    expect(response).to have_http_status(:not_found)

    expect(victim_listing.reload.attributes.slice("title", "status")).to eq("title" => nil, "status" => "on_sale")
    expect(victim_org.ticket_discount_codes).to be_empty
  end

  it "can't read, refund or resend another theater's order" do
    get manage_ticket_order_path(victim_order.id)
    expect(response).to have_http_status(:not_found)
    get manage_ticket_order_refund_path(victim_order.id), params: { ticket_ids: victim_order.tickets.pluck(:id) }
    expect(response).to have_http_status(:not_found)
    post manage_ticket_order_refund_path(victim_order.id), params: { ticket_ids: victim_order.tickets.pluck(:id) }
    expect(response).to have_http_status(:not_found)
    post manage_ticket_order_resend_path(victim_order.id)
    expect(response).to have_http_status(:not_found)

    expect(Stripe::Refund).not_to have_received(:create)
    expect(victim_order.reload.status).to eq("paid")
  end

  it "never lists another theater's orders or counts its money" do
    # (The search box echoes the code typed into it; what matters is no row.)
    get manage_ticket_orders_path, params: { q: victim_order.code }
    expect(response.body).not_to include(manage_ticket_order_path(victim_order.id))
    get manage_ticket_orders_path, params: { listing_id: victim_listing.id }
    expect(response.body).not_to include(manage_ticket_order_path(victim_order.id))

    expect(TicketBalance.summary(org).total_cents).to eq(0)
  end

  it "can't change another theater's door access" do
    grant = victim_org.ticketing_access_grants.create!(user: create(:user), access_level: "check_in")
    patch manage_ticketing_door_access_grant_path(grant), params: { access_level: "box_office" }
    expect(response).to have_http_status(:not_found)
    delete manage_ticketing_door_access_grant_path(grant)
    expect(response).to have_http_status(:not_found)
    expect(grant.reload.attributes.slice("access_level", "revoked_at")).to eq("access_level" => "check_in", "revoked_at" => nil)
  end

  # Ticket codes are global, so a scan at your own door can land on another
  # theater's ticket: it must stay unadmitted and say nothing about it.
  it "learns nothing from scanning another theater's ticket at its own door" do
    TicketingProfile.for(org).update!(enabled: true)
    own_listing = create(:ticket_listing, organization: org)
    victim_order.update!(buyer_name: "Dana Scully")
    ticket = victim_order.tickets.sole

    post door_check_in_path(own_listing), params: { code: "https://cocoscout.com/tickets/v/#{ticket.code}" }, as: :json

    body = response.parsed_body
    expect(body["kind"]).to eq("wrong_show")
    expect(body["message"]).to eq("This ticket isn't for this theater")
    expect(body.values_at("holder", "order_code", "ticket_id", "party")).to all(be_nil)
    expect(body["items"]).to eq([])
    expect(response.body).not_to include("Dana", victim_order.code, victim_listing.display_title)
    expect(ticket.reload.status).to eq("valid")
  end
end
