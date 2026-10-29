# frozen_string_literal: true

require "rails_helper"

# "Move tickets" on an order: pick the date (theirs, for another ticket
# type, or another one), the tickets and what each ticket type becomes, see
# what happens to the money, then move. The buyer's pages follow them.
RSpec.describe "Moving tickets to another date", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:friday) { create(:ticket_listing, organization: org) }
  let(:saturday) { create(:ticket_listing, organization: org, show: create(:show, production: friday.production)) }
  let!(:general) { friday.ticket_tiers.create!(name: "General", price_cents: 2_000) }
  let!(:saturday_general) { saturday.ticket_tiers.create!(name: "General", price_cents: 2_000) }
  let!(:saturday_student) { saturday.ticket_tiers.create!(name: "Student", price_cents: 1_500) }

  before do
    friday.show.update!(date_and_time: Time.zone.local(2026, 10, 16, 19, 30))
    saturday.show.update!(date_and_time: Time.zone.local(2026, 10, 17, 20, 0))
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  around { |example| travel_to(Time.zone.local(2026, 10, 2, 12)) { example.run } }

  def sold(count)
    order = TicketCheckout.start!(listing: friday, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_sale")
    order.reload
  end

  it "offers the move on the order, previews it, and moves the tickets" do
    order = sold(2)
    get manage_ticket_order_path(order.id)
    expect(response.body).to include("Move to another date", manage_ticket_order_exchange_path(order.id))

    get manage_ticket_order_exchange_path(order.id)
    expect(response.body).to include("Which date?", "Saturday, October 17 · 8:00 PM")
    expect(response.body).not_to include("Move 2 tickets")

    get manage_ticket_order_exchange_path(order.id, to_listing_id: saturday.id)
    expect(response.body).to include("General becomes", "Move 2 tickets", "Same price, so no money changes hands")

    get manage_ticket_order_exchange_path(order.id, to_listing_id: saturday.id, picked: "1",
                                                    ticket_ids: order.tickets.pluck(:id), tiers: { general.id => saturday_student.id })
    expect(response.body).to include("The new tickets cost $10.00 less")

    expect {
      post manage_ticket_order_exchange_path(order.id), params: { to_listing_id: saturday.id, ticket_ids: order.tickets.pluck(:id),
                                                                  tiers: { general.id => saturday_general.id }, email_them: "1" }
    }.to have_enqueued_mail(TicketOrderMailer, :moved)
    moved = TicketOrder.find_by!(exchanged_from_id: order.id)
    expect(response).to redirect_to(manage_ticket_order_path(moved.id))
    expect(flash[:notice]).to eq("Moved 2 tickets to Saturday, October 17.")

    get manage_ticket_order_path(moved.id)
    expect(response.body).to include("Moved here from", "order #{order.code}")
    get manage_ticket_order_path(order.id)
    expect(response.body).to include("Moved", "2 tickets moved to")

    # The buyer's old link points them to the new tickets.
    get tickets_order_path(token: order.token)
    expect(response.body).to include("Your tickets moved", "See the new tickets", tickets_order_path(token: moved.token))
  end

  it "explains why it can't move" do
    order = sold(1)
    saturday_general.update!(price_cents: 2_500)
    get manage_ticket_order_exchange_path(order.id, to_listing_id: saturday.id)
    expect(response.body).to include("Can&#39;t move these", "more than their $20.00 ticket")

    post manage_ticket_order_exchange_path(order.id), params: { to_listing_id: saturday.id, ticket_ids: order.tickets.pluck(:id) }
    expect(flash[:alert]).to include("more than their $20.00 ticket")
    expect(order.reload.status).to eq("paid")
  end

  it "offers only their own date, for another ticket type, when no other date is on sale" do
    order = sold(1)
    saturday.update!(status: "paused")
    get manage_ticket_order_exchange_path(order.id)
    expect(response.body).to include("Same date, another ticket type")
    expect(response.body).not_to include("Saturday, October 17")
  end

  # Tim, 2026-10-29: a Splatter Zone comp that should have been General
  # Admission, fixed without canceling and comping again.
  it "changes a comp to another ticket type on the same date, offering only types with seats" do
    splatter = friday.ticket_tiers.create!(name: "Splatter Zone", price_cents: 4_000)
    front = friday.ticket_tiers.create!(name: "Front Row", price_cents: 6_000, quantity: 1)
    guests = [ TicketComps::Guest.new(name: "Dana Scully", email: "dana@example.com", tier: splatter, quantity: 1),
               TicketComps::Guest.new(name: "Fox Mulder", email: nil, tier: front, quantity: 1) ]
    order = TicketComps.give!(friday, guests, by: superadmin, email_them: false).first

    get manage_ticket_order_path(order.id)
    expect(response.body).to include("Move to another date or ticket type", "They stay free and get new tickets")

    get manage_ticket_order_exchange_path(order.id, to_listing_id: friday.id)
    expect(response.body).to include("Same date, another ticket type", "Splatter Zone becomes", "These tickets were free")
    page = Nokogiri::HTML(response.body)
    options = page.css("select[name='tiers[#{splatter.id}]'] option").to_h { |o| [ o.text, o["disabled"].present? ] }
    expect(options).to eq("Choose a ticket type" => false, "General ($20.00)" => false, "Front Row ($60.00) · no seats left" => true)
    expect(response.body).not_to include("Change 1 ticket")

    get manage_ticket_order_exchange_path(order.id, to_listing_id: friday.id, picked: "1", ticket_ids: order.tickets.pluck(:id),
                                                    tiers: { splatter.id => general.id })
    expect(response.body).to include("Change 1 ticket to General", "They didn't pay for these, so the new ones are free too")

    get manage_ticket_order_exchange_path(order.id, to_listing_id: friday.id, picked: "1", ticket_ids: order.tickets.pluck(:id),
                                                    tiers: { splatter.id => front.id })
    expect(response.body).to include("Front Row has no seats left")

    expect {
      post manage_ticket_order_exchange_path(order.id), params: { to_listing_id: friday.id, ticket_ids: order.tickets.pluck(:id),
                                                                  tiers: { splatter.id => general.id }, email_them: "1" }
    }.to have_enqueued_mail(TicketOrderMailer, :moved)
    changed = TicketOrder.find_by!(exchanged_from_id: order.id)
    expect(flash[:notice]).to eq("Changed 1 ticket to General.")
    expect(changed.tickets.pluck(:ticket_tier_id, :ticket_listing_id)).to eq([ [ general.id, friday.id ] ])

    get manage_ticket_order_path(changed.id)
    expect(response.body).to include("Changed from another ticket type on", "order #{order.code}")
    get manage_ticket_order_path(order.id)
    expect(response.body).to include("1 ticket changed to another ticket type", "Changed to another ticket type")
  end

  it "can't reach another theater's order, or move into another theater's show" do
    other_org = create(:organization, :pro)
    other = create(:ticket_order, ticket_listing: create(:ticket_listing, organization: other_org), status: "paid", paid_at: Time.current)
    get manage_ticket_order_exchange_path(other.id)
    expect(response).to have_http_status(:not_found)
    post manage_ticket_order_exchange_path(other.id), params: { to_listing_id: saturday.id }
    expect(response).to have_http_status(:not_found)

    order = sold(1)
    elsewhere = create(:ticket_listing, organization: other_org)
    post manage_ticket_order_exchange_path(order.id), params: { to_listing_id: elsewhere.id, ticket_ids: order.tickets.pluck(:id) }
    expect(flash[:alert]).to include("Choose another date")
    expect(order.reload.status).to eq("paid")
  end
end
