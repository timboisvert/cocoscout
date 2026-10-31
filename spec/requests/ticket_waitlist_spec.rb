# frozen_string_literal: true

require "rails_helper"

# The waitlist (advanced ticketing plan §7b, V1.4 step 2): a sold-out date
# takes names when the production's waitlist is on; returned seats go to the
# first party they fit, held 30 minutes, by email; the box office sees the
# line and can write to it.
RSpec.describe "Ticket waitlist", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true, waitlist: true) }
  let(:listing) { TicketListing.create!(show: create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19)), status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_500, quantity: 2) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_wait")) }

  def buy(count)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: "First Buyer", buyer_email: "first@example.com")
    TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_#{SecureRandom.hex(3)}")
    order.reload
  end

  def join(name, email, quantity = 1)
    post tickets_join_waitlist_path(org: "starsandgarters", event: listing.slug), params: { name: name, email: email, quantity: quantity }
    TicketWaitlistEntry.find_by!(email: email)
  end

  it "takes names only when the date is sold out and the production's waitlist is on" do
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).not_to include("Join the waitlist")

    buy(2)
    expect(listing.inventory.sold_out?).to be(true)
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to include("Join the waitlist", "Put me on the list")
    expect(Ticketing::ListingPayload.for(listing)[:waitlist]).to be(true)

    setup.update!(waitlist: false)
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).not_to include("Join the waitlist")
    post tickets_join_waitlist_path(org: "starsandgarters", event: listing.slug), params: { name: "Late Larry", email: "larry@example.com" }
    expect(response).to redirect_to(tickets_event_path(org: "starsandgarters", event: listing.slug))
    expect(flash[:alert]).to include("isn't taking a waitlist")
    expect(TicketWaitlistEntry.count).to eq(0)
  end

  it "puts a party on the list, emails them, shows their place, and lets them leave" do
    buy(2)
    perform_enqueued_jobs do
      entry = join("Avery Waits", "avery@example.com", 2)
      expect(response).to redirect_to(tickets_waitlist_path(token: entry.token))
      expect(entry).to have_attributes(status: "waiting", quantity: 2, position: 1, organization_id: org.id)
    end
    joined = ActionMailer::Base.deliveries.last
    expect(joined.to).to eq([ "avery@example.com" ])
    expect(joined.subject).to eq("You're on the list for Boylesque")

    # Same email twice is one place in line.
    post tickets_join_waitlist_path(org: "starsandgarters", event: listing.slug), params: { name: "Avery Again", email: "avery@example.com" }
    expect(flash[:alert]).to be_present
    expect(TicketWaitlistEntry.count).to eq(1)

    entry = TicketWaitlistEntry.first
    get tickets_waitlist_path(token: entry.token)
    expect(response.body).to include("You're on the waitlist", "2 tickets", "first in line", "Leave the list")

    delete tickets_waitlist_path(token: entry.token)
    expect(entry.reload.status).to eq("removed")
    follow_redirect!
    expect(response.body).to include("You've left the list")
  end

  it "offers returned seats to the first party they fit, holds them 30 minutes, and marks the sale when they pay" do
    paid = buy(2)
    big = join("Big Party", "big@example.com", 3)
    pair = join("Pat Pair", "pat@example.com", 2)
    one = join("Solo Sam", "sam@example.com", 1)

    perform_enqueued_jobs do
      TicketOrderRefund.issue!(paid.reload, ticket_ids: [ paid.tickets.first.id ])
    end
    # One seat came back: the three-seat and two-seat parties keep waiting; the single gets it.
    expect(big.reload.status).to eq("waiting")
    expect(pair.reload.status).to eq("waiting")
    expect(one.reload.status).to eq("offered")
    offer = one.offer_order
    expect(offer).to have_attributes(buyer_email: "sam@example.com", waitlist_offer: true, status: "pending")
    expect(offer.expires_at).to be_within(2.minutes).of(30.minutes.from_now)
    expect(offer.tickets.count).to eq(1)
    expect(listing.inventory.sold_out?).to be(true)

    offer_mail = ActionMailer::Base.deliveries.find { |m| m.to == [ "sam@example.com" ] && m.subject.match?(/seat|held|yours/i) }
    expect(offer_mail).to be_present
    expect(offer_mail.body.encoded).to include(tickets_checkout_path(token: offer.token))

    get tickets_waitlist_path(token: one.token)
    expect(response.body).to include("Seats are held for you", "Buy your tickets")

    TicketPurchaseSettlement.settle!(offer.ticket_purchase, payment_intent_id: "pi_waitlist")
    expect(one.reload.status).to eq("bought")
    expect(BooksReconciliation.check(org)).to eq([])
  end

  it "passes a lapsed offer to the next party" do
    paid = buy(2)
    first = join("First Up", "first-up@example.com", 1)
    second = join("Second Up", "second@example.com", 1)
    perform_enqueued_jobs { TicketOrderRefund.issue!(paid.reload, ticket_ids: [ paid.tickets.first.id ]) }
    expect(first.reload.status).to eq("offered")
    expect(second.reload.status).to eq("waiting")

    travel 31.minutes do
      perform_enqueued_jobs { WaitlistOfferJob.perform_later }
    end
    expect(first.reload.status).to eq("missed")
    expect(second.reload.status).to eq("offered")
    expect(second.offer_order.tickets.count).to eq(1)
    missed_mail = ActionMailer::Base.deliveries.find { |m| m.to == [ "first-up@example.com" ] && m.subject != ActionMailer::Base.deliveries.first.subject }
    expect(missed_mail).to be_present
  end

  it "shows the box office the line, sends a note with a preview first, and takes someone off" do
    buy(2)
    avery = join("Avery Waits", "avery@example.com", 2)
    join("Blake Behind", "blake@example.com", 1)

    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Waitlist", "2 parties waiting")

    get manage_ticket_listing_waitlist_path(listing)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("In line", "Avery Waits", "Blake Behind", "Email everyone waiting", "Offer free seats now")
    expect(response.body).to include("waitlist-note", "{{first_name}}")

    perform_enqueued_jobs do
      post manage_ticket_listing_waitlist_note_path(listing), params: { person_ids: [ avery.id ], subject: "More seats for {{first_name}}", body: "<p>Hi {{first_name}}, we added a late show.</p>" }
    end
    expect(response).to redirect_to(manage_ticket_listing_waitlist_path(listing))
    note = ActionMailer::Base.deliveries.last
    expect(note.to).to eq([ "avery@example.com" ])
    expect(note.subject).to eq("More seats for Avery")
    expect(note.body.encoded).to include("Hi Avery, we added a late show.")

    # Nothing free: offering now says so.
    post manage_ticket_listing_waitlist_offer_path(listing)
    expect(flash[:notice]).to include("No seats are free")

    delete manage_ticket_listing_waitlist_entry_path(listing, avery)
    expect(avery.reload.status).to eq("removed")
    expect(flash[:notice]).to include("Avery Waits is off the list")
  end

  it "is off until the production's Sales settings turn it on" do
    setup.update!(waitlist: false)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
    get manage_edit_production_ticketing_path(production, section: "sales")
    expect(response.body).to include("production_ticketing[waitlist]")

    patch manage_update_production_ticketing_path(production, section: "sales"), params: { production_ticketing: { waitlist: "1", max_per_order: 10, fee_mode: "buyer" } }
    expect(setup.reload.waitlist).to be(true)

    buy(2)
    get manage_ticket_listing_waitlist_path(listing)
    expect(response.body).not_to include("This production's waitlist is off")
  end
end
