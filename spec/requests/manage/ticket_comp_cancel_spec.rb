# frozen_string_literal: true

require "rails_helper"

# A comp that isn't coming: the order page cancels the tickets instead of
# refunding them. No money moves, the seats come free, nobody is emailed.
RSpec.describe "Canceling a comp", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 5) }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  it "cancels a comp's tickets from the order page" do
    guest = TicketComps::Guest.new(name: "Dana Scully", email: "dana@example.com", tier: general, quantity: 2)
    order = TicketComps.give!(listing, [ guest ], by: superadmin).first
    expect(listing.inventory.remaining).to eq(3)

    get manage_ticket_order_path(order.id)
    expect(response.body).to include("Cancel tickets", "Not coming after all?")
    expect(response.body).not_to include("Review refund")

    get manage_ticket_order_refund_path(order.id, ticket_ids: order.tickets.pluck(:id), item_ids: [ "" ])
    expect(response.body).to include("Cancel 2 tickets for Dana Scully", "no money moves")

    expect {
      post manage_ticket_order_refund_path(order.id), params: { ticket_ids: order.tickets.pluck(:id), item_ids: [ "" ], keep_fees: "0" }
    }.not_to have_enqueued_job(TicketRefundEmailJob)
    expect(response).to redirect_to(manage_ticket_order_path(order.id))
    follow_redirect!
    expect(response.body).to include("Canceled 2 tickets for Dana Scully", "Canceled tickets")
    expect([ order.reload.status, order.tickets.pluck(:status).uniq, order.refunded_cents ]).to eq([ "refunded", [ "void" ], 0 ])
    expect(listing.inventory.remaining).to eq(5)
    expect(OrgCashEntry.where(organization: org)).to be_empty

    get tickets_order_path(token: order.token)
    expect(response.body).to include("These tickets were canceled")

    # Everywhere the order is listed, it reads as canceled: struck through, with a chip.
    get manage_ticket_orders_path
    expect(response.body).to include("line-through", ">Canceled<")
    get manage_ticket_listing_path(listing, guests: "refunded")
    expect(response.body).to include("line-through", ">Canceled<", "2 × General")
  end
end
