# frozen_string_literal: true

require "rails_helper"

# Group sales (advanced ticketing plan §3, V1.4 step 3): a block of seats
# held for a group on an invoice, tickets when it's paid, the seats back on
# sale when it isn't paid in time.
RSpec.describe "Ticket group sales", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true) }
  let(:listing) { TicketListing.create!(show: create(:show, production: production, date_and_time: 30.days.from_now.change(hour: 19)), status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_500, quantity: 50) }

  before do
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(double("intent", latest_charge: double("charge", balance_transaction: double("txn", fee: 300))))
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  def book(seats: 20, comps: 2, price: "20.00", due_on: Date.current + 10, release_on: Date.current + 14)
    post manage_ticket_listing_groups_path(listing), params: { ticket_group_booking: {
      name: "Lincoln Park High School", contact_name: "Dana Teacher", contact_email: "dana@lphs.test", contact_phone: "312-555-0100",
      seat_count: seats, comp_count: comps, ticket_tier_id: general.id, price: price, due_on: due_on.iso8601, release_on: release_on.iso8601, notes: "Bus arrives 6:30"
    } }
    TicketGroupBooking.last
  end

  def pay_online(invoice)
    InvoiceCollection.settle!(invoice, double("session", id: "cs_group_#{invoice.id}", payment_intent: "pi_group", amount_total: invoice.unpaid_cents))
  end

  it "holds the seats on an invoice, tells the leader, and keeps the block out of sale" do
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Groups", "Blocks of seats on an invoice")
    get manage_new_ticket_listing_group_path(listing)
    expect(response.body).to include("Book a group", "Group rate a seat", "Seats held until")

    booking = nil
    perform_enqueued_jobs { booking = book }
    expect(response).to redirect_to(manage_ticket_listing_group_path(listing, booking))
    expect(booking).to have_attributes(status: "booked", seat_count: 20, comp_count: 2, price_cents: 2_000, organization_id: org.id)
    expect(booking.quantity_hold).to have_attributes(quantity: 22, ticket_tier_id: general.id, released_at: nil)
    expect(listing.inventory.remaining).to eq(28)
    expect(listing.inventory.remaining(tier: general)).to eq(28)
    expect(listing.inventory.fits?({ general => 29 })).to be(false)

    invoice = booking.invoice
    expect(invoice).to have_attributes(status: "open", total_cents: 40_000, category_key: "tickets", bill_to_name: "Lincoln Park High School", bill_to_email: "dana@lphs.test", show_id: listing.show_id, pay_by_bank: true)
    expect(invoice.invoice_lines.map(&:description)).to eq([ "20 seats, Boylesque, #{listing.show.date_and_time.strftime('%A, %B %-d, %Y at %-l:%M %p')}", "2 chaperone seats, no charge" ])
    expect(ChartOfAccounts.account(org, :owed_to_you).natural_balance_cents).to eq(40_000)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "dana@lphs.test" ])
    expect(mail.subject).to eq("22 seats held for Lincoln Park High School: Boylesque, #{listing.show.date_and_time.strftime('%A, %B %-d')}")
    expect(mail.body.encoded).to include(tickets_group_path(token: booking.token), "$400.00")

    follow_redirect!
    expect(response.body).to include("Lincoln Park High School", "Seats held", "Issue tickets now", "Release the seats", invoice.display_number)
    get manage_ticket_listing_groups_path(listing)
    expect(response.body).to include("Lincoln Park High School", "20 seats + 2 chaperone", "held until")
  end

  it "won't hold more than the seats left" do
    book(seats: 60, comps: 0)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Only 50 seats of that type are left")
    expect(TicketGroupBooking.count).to eq(0)
  end

  it "turns the paid invoice into tickets with the leader's names, and takes 50¢ a paid seat when paid through our pay page" do
    booking = book
    get tickets_group_path(token: booking.token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("22 seats are held for you", "Pay $400.00", "Who's coming", pay_invoice_path(token: booking.invoice.payment_token!))

    patch tickets_group_names_path(token: booking.token), params: { names: "Avery Smith\nBlake Jones\n\nCasey Lee" }
    expect(booking.reload.names_list).to eq([ "Avery Smith", "Blake Jones", "Casey Lee" ])

    perform_enqueued_jobs { expect(pay_online(booking.invoice)).to be(true) }
    booking.reload
    expect(booking.status).to eq("ticketed")
    expect(booking.quantity_hold.released_at).to be_present
    order = booking.ticket_order
    expect(order).to have_attributes(channel: "group", money_path: "external", status: "paid", buyer_name: "Lincoln Park High School", buyer_email: "dana@lphs.test")
    expect(order.tickets.count).to eq(22)
    expect(order.tickets.order(:id).limit(3).pluck(:holder_name)).to eq([ "Avery Smith", "Blake Jones", "Casey Lee" ])
    expect(order.tickets.where(discount_cents: 2_000).count).to eq(2)
    expect(order.platform_fee_cents).to eq(0)
    expect(listing.inventory.remaining).to eq(28)
    expect(listing.inventory.sold).to eq(22)

    # The invoice is the money; the fee is the balance's only other move.
    expect(booking.invoice.reload).to be_paid
    expect(OrgCashEntry.where(organization: org).pluck(:entry_type, :amount_cents)).to contain_exactly([ "invoice_payment", 39_700 ], [ "ticket_sale", -1_000 ])
    expect(CocoScoutLedgerEntry.where(source: booking).pluck(:entry_type, :amount_cents)).to eq([ [ "ticket_fee", 1_000 ] ])
    expect(ChartOfAccounts.account(org, :owed_to_you).natural_balance_cents).to eq(0)
    # Our 50¢ a seat, plus the card fee the invoice payment booked.
    expect(ChartOfAccounts.account(org, :ticketing_fees).natural_balance_cents).to eq(1_300)
    expect(BooksReconciliation.check(org)).to eq([])

    ready = ActionMailer::Base.deliveries.find { |m| m.subject.start_with?("Your tickets for Boylesque") }
    expect(ready).to be_present
    get tickets_group_path(token: booking.token)
    expect(response.body).to include("Your tickets are ready", "All tickets, one PDF", tickets_order_pdf_path(token: order.token, format: :pdf))

    # Names can still change once the tickets exist.
    patch tickets_group_names_path(token: booking.token), params: { names: "Zed First" }
    expect(order.tickets.order(:id).first.reload.holder_name).to eq("Zed First")
  end

  it "takes no fee on a check, and a trusted group can have its tickets before paying" do
    booking = book
    post manage_issue_ticket_listing_group_path(listing, booking)
    expect(booking.reload.status).to eq("ticketed")
    expect(booking.invoice).to be_open
    expect(booking.ticket_order.tickets.count).to eq(22)

    post manage_payments_money_invoice_path(booking.invoice), params: { amount: "400.00", via: "check", reference: "1042" }
    expect(booking.invoice.reload).to be_paid
    expect(booking.reload.ticket_order.tickets.count).to eq(22)
    expect(OrgCashEntry.where(organization: org, entry_type: "ticket_sale")).to be_empty
    expect(BooksReconciliation.check(org)).to eq([])
  end

  it "warns the leader, then releases the seats and cancels the invoice when the clock runs out" do
    booking = book(due_on: Date.current + 1, release_on: Date.current + 2)
    perform_enqueued_jobs { GroupHoldReleaseJob.perform_now }
    expect(booking.reload.warned_at).to be_present
    expect(booking.status).to eq("booked")
    warning = ActionMailer::Base.deliveries.last
    expect(warning.subject).to include("go back on sale")

    travel_to(Date.current + 3) do
      perform_enqueued_jobs { GroupHoldReleaseJob.perform_now }
    end
    booking.reload
    expect(booking.status).to eq("released")
    expect(booking.quantity_hold.released_at).to be_present
    expect(booking.invoice.reload).to be_void
    expect(listing.inventory.remaining).to eq(50)
    expect(ChartOfAccounts.account(org, :owed_to_you).natural_balance_cents).to eq(0)
    expect(ActionMailer::Base.deliveries.last.subject).to eq("The seats held for Lincoln Park High School were released")
    get tickets_group_path(token: booking.token)
    expect(response.body).to include("These seats were released")
  end

  it "lets the box office release a block by hand, and cancelling its invoice does the same" do
    first = book
    second = book
    post manage_release_ticket_listing_group_path(listing, first)
    expect(first.reload.status).to eq("canceled")
    expect(first.invoice.reload).to be_void
    expect(listing.inventory.remaining).to eq(28)

    post manage_void_money_invoice_path(second.invoice), params: { reason: "They changed their minds" }
    expect(second.reload.status).to eq("canceled")
    expect(listing.inventory.remaining).to eq(50)
  end
end
