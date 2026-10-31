# frozen_string_literal: true

require "rails_helper"

# Season subscriptions (advanced ticketing plan §2a, V1.4 step 7): a pass
# whose buyers keep the same seats at every date, picked on one map; next
# season, their seats held for them and renewed from an emailed link.
RSpec.describe "Ticket subscriptions", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let!(:location) { create(:location, organization: org, name: "The Lodge") }
  let(:room) { location.default_room }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true) }
  let!(:premium) { setup.ticket_tiers.create!(name: "Premium", price_cents: 4_000, position: 0) }
  let!(:show_one) { create(:show, production: production, location: location, date_and_time: 20.days.from_now.change(hour: 19)) }
  let!(:show_two) { create(:show, production: production, location: location, date_and_time: 27.days.from_now.change(hour: 19)) }
  let(:chart) do
    chart = org.seat_charts.create!(location_space: room, name: "Concert layout")
    orchestra = chart.sections.create!(name: "Orchestra", kind: "rows", position: 0)
    orchestra.add_rows!(count: 2, per_row: 6, first_row: "A", first_number: 1)
    chart.relayout!
    chart.update!(status: "active")
    premium.zones.create!(seat_section: orchestra)
    setup.update!(seating_mode: "reserved", seat_chart: chart)
    chart
  end
  let(:orchestra) { chart.sections.first }
  let(:listings) { chart; ProductionTicketingDates.sync!(setup); [ show_one, show_two ].map { |s| TicketListing.find_by!(show: s) } }
  let(:date_tiers) { listings.map { |l| l.ticket_tiers.find_by!(source_tier_id: premium.id) } }

  def seat(label) = orchestra.seats.find_by!(label: label)
  def pay!(order, name:, email:)
    order.ticket_purchase.ticket_orders.each { |o| o.update!(buyer_name: name, buyer_email: email) }
    TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_#{SecureRandom.hex(3)}")
  end

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "sells the same seats at every date, keeps them off the map for others, and welcomes the subscriber" do
    get manage_new_ticket_pass_path
    expect(response.body).to include("Subscription", "The same seats at every show you pick below")

    pass = org.ticket_passes.create!(name: "Season seats", kind: "subscription", price_cents: 7_000, status: "on_sale",
                                     pass_shows_attributes: date_tiers.map { |t| { ticket_tier_id: t.id } })
    expect(pass.pass_shows.count).to eq(2)

    get tickets_pass_path(org: "starsandgarters", pass: pass.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pick your seats", "data-seat-map-payload-value", "A subscription: your seats at 2 shows")

    post tickets_pass_checkout_path(org: "starsandgarters", pass: pass.slug), params: { seat_ids: [ seat("B 3").id, seat("B 4").id ] }
    expect(response).to redirect_to(%r{/tickets/checkout/})
    order = TicketOrder.order(:id).last
    purchase = order.ticket_purchase
    expect(purchase.ticket_orders.count).to eq(2)
    expect(purchase.ticket_orders.flat_map { |o| o.tickets.map(&:seat_label) }).to eq([ "B 3", "B 4", "B 3", "B 4" ])
    subscription = purchase.ticket_subscriptions.sole
    expect(subscription).to have_attributes(status: "pending", quantity: 2)

    # Someone else can't pick B 3 while it's in a cart, and not after it's sold.
    post tickets_pass_checkout_path(org: "starsandgarters", pass: pass.slug), params: { seat_ids: [ seat("B 3").id ] }
    expect(flash[:alert]).to include("isn't free on every date")

    perform_enqueued_jobs { pay!(order, name: "Bella Swan", email: "bella@example.com") }
    subscription.reload
    expect(subscription).to have_attributes(status: "active", buyer_email: "bella@example.com")
    expect(subscription.seat_labels).to eq([ "B 3", "B 4" ])
    expect(subscription.follower).to be_present
    welcome = ActionMailer::Base.deliveries.find { |m| m.subject == "Your seats for Season seats" }
    expect(welcome.to).to eq([ "bella@example.com" ])
    expect(welcome.html_part.body.to_s).to include("B 3 and B 4", "all 2 shows", tickets_subscription_path(token: subscription.token))

    get tickets_subscription_path(token: subscription.token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("B 3 and B 4", "Your dates", "Subscribed")
    expect(response.body).not_to include("Renew my seats")

    # The pass page greys those seats out on every date.
    payload = Ticketing::Subscriptions.payload(pass)
    statuses = payload[:sections].first[:seats].index_by { |s| s[:label] }
    expect(statuses["B 3"][:status]).to eq("sold")
    expect(statuses["B 5"][:status]).to eq("free")

    # Best available for a buyer who lets us choose: front and center, the same at both dates.
    post tickets_pass_checkout_path(org: "starsandgarters", pass: pass.slug), params: { quantity: 1 }
    second = TicketOrder.order(:id).last
    labels = second.ticket_purchase.ticket_orders.map { |o| o.tickets.sole.seat_label }.uniq
    expect(labels.size).to eq(1)
    expect(labels.first).to start_with("A ")

    get manage_ticket_pass_path(pass)
    expect(response.body).to include("Subscribers", "Bella Swan", "B 3 and B 4")
    expect(BooksReconciliation.check(org)).to be_empty
  end

  it "opens renewal next season: seats held until the close, an emailed Renew link, the holds let go after" do
    pass = org.ticket_passes.create!(name: "Season seats", kind: "subscription", price_cents: 7_000, status: "on_sale",
                                     pass_shows_attributes: date_tiers.map { |t| { ticket_tier_id: t.id } })
    order = TicketCheckout.start_pass!(pass: pass, quantity: 2, seats: [ seat("B 3").id, seat("B 4").id ])
    pay!(order, name: "Bella Swan", email: "bella@example.com")
    subscription = pass.subscriptions.sole
    other_order = TicketCheckout.start_pass!(pass: pass, quantity: 1, seats: [ seat("A 1").id ])
    pay!(other_order, name: "Edward Cullen", email: "edward@example.com")

    # Next season: two new dates on the same chart.
    next_one = create(:show, production: production, location: location, date_and_time: 60.days.from_now.change(hour: 19))
    next_two = create(:show, production: production, location: location, date_and_time: 67.days.from_now.change(hour: 19))
    ProductionTicketingDates.sync!(setup)
    next_tiers = [ next_one, next_two ].map { |s| TicketListing.find_by!(show: s).ticket_tiers.find_by!(source_tier_id: premium.id) }
    next_pass = org.ticket_passes.create!(name: "Season seats, next year", kind: "subscription", price_cents: 7_500, status: "on_sale",
                                          renews_from: pass, pass_shows_attributes: next_tiers.map { |t| { ticket_tier_id: t.id } })

    get manage_ticket_pass_path(next_pass)
    expect(response.body).to include("Renewal from Season seats", "2 subscribers to invite", "Open renewal")

    closes = 10.days.from_now.change(hour: 12)
    perform_enqueued_jobs do
      post manage_ticket_pass_renewal_path(next_pass), params: { closes_at: closes.strftime("%Y-%m-%dT%H:%M") }
    end
    expect(flash[:notice]).to include("2 subscribers invited")
    subscription.reload
    expect(subscription).to have_attributes(status: "renewal_open", renewal_pass: next_pass)
    holds = subscription.seat_holds.to_a
    expect(holds.map(&:ticket_listing_id)).to match_array(next_tiers.map(&:ticket_listing_id))
    expect(holds.flat_map { |h| h.seats.map(&:label) }).to match_array([ "B 3", "B 4", "B 3", "B 4" ])
    renewal = ActionMailer::Base.deliveries.find { |m| m.to == [ "bella@example.com" ] && m.subject.include?("waiting") }
    expect(renewal.html_part.body.to_s).to include("B 3 and B 4", closes.strftime("%B %-d, %Y"), tickets_subscription_path(token: subscription.token))

    # A stranger can't take a held seat on the new pass; the subscriber can.
    post tickets_pass_checkout_path(org: "starsandgarters", pass: next_pass.slug), params: { seat_ids: [ seat("B 3").id ] }
    expect(flash[:alert]).to include("isn't free on every date")
    expect(Ticketing::Subscriptions.free_seats(next_pass).map(&:label)).not_to include("B 3", "A 1")

    get tickets_subscription_path(token: subscription.token)
    expect(response.body).to include("Renew my seats", "Season seats, next year")
    post tickets_subscription_renew_path(token: subscription.token)
    expect(response).to redirect_to(%r{/tickets/checkout/})
    renewed_order = TicketOrder.order(:id).last
    expect(renewed_order.ticket_purchase.ticket_orders.flat_map { |o| o.tickets.map(&:seat_label) }).to eq([ "B 3", "B 4", "B 3", "B 4" ])
    pay!(renewed_order, name: "Bella Swan", email: "bella@example.com")
    new_sub = next_pass.subscriptions.sole
    expect(new_sub).to have_attributes(status: "active", renewed_from: subscription, seat_ids: [ seat("B 3").id, seat("B 4").id ])
    expect(subscription.reload.status).to eq("renewed")
    expect(subscription.seat_holds.map(&:live?)).to all(be(false))

    get tickets_subscription_path(token: subscription.token)
    expect(response.body).to include("Renewed:")

    # Edward lets it lapse: a reminder near the close, then his seat goes on sale.
    travel_to(closes - 2.days) { Ticketing::Subscriptions.sweep! }
    edward = pass.subscriptions.find_by!(buyer_email: "edward@example.com")
    expect(edward.reload.renewal_reminders).to eq(2)
    travel_to(closes + 1.hour) do
      Ticketing::Subscriptions.sweep!
      expect(edward.reload.status).to eq("released")
      expect(Ticketing::Subscriptions.free_seats(next_pass).map(&:label)).to include("A 1")
    end

    get manage_ticket_pass_path(next_pass)
    expect(response.body).to include("1 renewal in", "1 let go", "Bella Swan")
    expect(BooksReconciliation.check(org)).to be_empty
  end
end
