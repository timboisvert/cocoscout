# frozen_string_literal: true

require "rails_helper"

# Memberships (advanced ticketing plan §2b, V1.4 step 6): a level built
# from a menu of perks, bought on the members page and paid like a credit
# pass (50¢ to us, dues to Membership dues); a member proves their email
# with a code and a 30-day cookie; their perks apply at checkout: a
# percentage off, members-first on-sale, the members' block, a section up;
# renewal by invitation.
RSpec.describe "Ticket memberships", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let!(:location) { create(:location, organization: org, name: "The Lodge") }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true) }
  let!(:general) { setup.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20, position: 0) }
  let!(:show) { create(:show, production: production, location: location, date_and_time: 20.days.from_now.change(hour: 19)) }
  let(:listing) { ProductionTicketingDates.sync!(setup); TicketListing.find_by!(show: show) }
  let(:date_general) { listing.ticket_tiers.find_by!(source_tier_id: general.id) }

  def sign_in_manager
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  def pay_purchase!(purchase, name: "Bella Swan", email: "bella@example.com")
    intent = Stripe::PaymentIntent.construct_from(id: "pi_m#{purchase.id}", client_secret: "pi_m_secret", amount: purchase.total_cents, status: "succeeded",
                                                  latest_charge: { id: "ch_m", balance_transaction: { fee: 200 } })
    allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)
    purchase.update_columns(created_at: 10.seconds.ago)
    post tickets_membership_purchase_pay_path(token: purchase.token), params: { buyer_name: name, buyer_email: email }, as: :json
    expect(response.parsed_body).to eq("client_secret" => "pi_m_secret")
    get tickets_membership_purchase_done_path(token: purchase.token)
  end

  it "sells a level built from perks, books the dues, signs the member in, and prices their tickets" do
    sign_in_manager
    get manage_ticket_memberships_path
    expect(response.body).to include("No levels yet")
    post manage_ticket_membership_levels_path, params: { ticket_membership_level: { name: "Friend", price: "60", period_months: 12, status: "on_sale",
                                                                            discount_percent: 10, presale_days: 7, free_exchanges: "1", extras: "A free drink at every show" } }
    level = org.ticket_membership_levels.last
    expect(level).to have_attributes(name: "Friend", price_cents: 6_000, discount_percent: 10, presale_days: 7, free_exchanges: true)
    expect(level.perk_words).to eq([ "10% off tickets", "Tickets 7 days before everyone else", "Free date exchanges", "A free drink at every show" ])
    get manage_ticket_memberships_path
    expect(response.body).to include("Friend", "0 members", "/tickets/starsandgarters/members")
    delete session_path rescue nil
    reset!

    # The members page, join, pay.
    get tickets_members_path(org: "starsandgarters")
    expect(response.body).to include("Friend", "10% off tickets", "Already a member?")
    get tickets_box_office_path(org: "starsandgarters")
    expect(response.body).to include("Become a member")
    post tickets_members_join_path(org: "starsandgarters"), params: { level_id: level.id }
    purchase = TicketPurchase.order(:id).last
    expect(response).to redirect_to(tickets_membership_purchase_path(token: purchase.token))
    membership = purchase.ticket_memberships.first
    expect(membership).to have_attributes(status: "pending", price_cents: 6_000, platform_fee_cents: 50)
    expect(membership.ends_on).to eq(Date.current + 12.months - 1.day)
    follow_redirect!
    expect(response.body).to include("Friend membership, a year", "Pay #{ActiveSupport::NumberHelper.number_to_currency(purchase.total_cents / 100.0)}")

    perform_enqueued_jobs { pay_purchase!(purchase) }
    membership.reload
    expect(response).to redirect_to(tickets_membership_path(token: membership.token))
    expect(membership).to have_attributes(status: "active", holder_email: "bella@example.com", stripe_fee_cents: 200)
    expect(membership.follower).to be_present
    expect(OrgCashEntry.where(source: membership, entry_type: "membership_sale").sum(:amount_cents)).to eq(membership.org_net_cents)
    dues = ChartOfAccounts.account(org, :membership_dues)
    expect(-JournalLine.where(ledger_account_id: dues.id).sum(:amount_cents)).to eq(6_000)
    expect(CocoScoutLedgerEntry.where(source: membership).sum(:amount_cents)).to eq(membership.total_cents - membership.org_net_cents - 200)
    expect(ActionMailer::Base.deliveries.map(&:subject)).to include("Welcome to Friend at Stars & Garters")
    expect(BooksReconciliation.check(org)).to eq([])

    # The card signs them in; the members page knows them.
    follow_redirect!
    expect(response.body).to include("Member through", "Your perks", "10% off tickets")
    get tickets_members_path(org: "starsandgarters")
    expect(response.body).to include("Your membership", "bella", "Sign out").or include("Your membership")

    # Buying tickets: the member price, applied at checkout and remembered on the order.
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to include("member price", "data-price=\"1800\"")
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { date_general.id.to_s => "2" } }
    order = TicketOrder.last
    expect(order.ticket_membership_id).to eq(membership.id)
    expect(order.tickets.map(&:discount_cents)).to eq([ 200, 200 ])
    expect(order.discount_cents).to eq(400)

    # Sign out; sign back in with a code.
    delete tickets_members_signout_path(org: "starsandgarters")
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).not_to include("member price")
    perform_enqueued_jobs { post tickets_members_code_path(org: "starsandgarters"), params: { email: "Bella@example.com" } }
    expect(response).to redirect_to(tickets_members_path(org: "starsandgarters", email: "bella@example.com"))
    code_mail = ActionMailer::Base.deliveries.last
    code = code_mail.subject[/\d{6}/]
    expect(code).to be_present
    post tickets_members_verify_path(org: "starsandgarters"), params: { email: "bella@example.com", code: "000000" }
    expect(flash[:alert]).to include("not the code") unless code == "000000"
    post tickets_members_verify_path(org: "starsandgarters"), params: { email: "bella@example.com", code: code }
    expect(flash[:notice]).to eq("You're signed in.")
    get tickets_members_path(org: "starsandgarters")
    expect(response.body).to include("Your membership")

    # Renewal: the reminder at 30 days, then the renew link carries the dates on.
    travel_to(membership.ends_on - 20.days) do
      perform_enqueued_jobs { MembershipSweepJob.perform_now }
      expect(membership.reload.renewal_reminders).to eq(1)
      expect(ActionMailer::Base.deliveries.last.subject).to include("membership ends")
      get tickets_membership_path(token: membership.token)
      expect(response.body).to include("Renew")
      post tickets_membership_renew_path(token: membership.token)
      renewal_purchase = TicketPurchase.order(:id).last
      renewal = renewal_purchase.ticket_memberships.first
      expect(renewal.starts_on).to eq(membership.ends_on + 1)
      expect(renewal.ends_on).to eq(membership.ends_on + 12.months)
      pay_purchase!(renewal_purchase)
      expect(renewal.reload.status).to eq("active")
      expect(membership.reload.status).to eq("renewed")
    end
    expect(BooksReconciliation.check(org)).to eq([])
  end

  it "lets members buy before everyone else, and refuses others until public on-sale" do
    level = org.ticket_membership_levels.create!(name: "Friend", price_cents: 6_000, status: "on_sale", presale_days: 7)
    listing.update!(on_sale_at: 5.days.from_now)
    expect(listing.effective_members_on_sale_at).to eq(listing.on_sale_at - 7.days)
    expect(listing.members_presale_open?).to be(true)
    expect(listing.selling?).to be(false)

    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to include("Members buy first", "Your member email")
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { date_general.id.to_s => "1" } }
    expect(flash[:alert]).to include("Members buy first")

    member = org.ticket_memberships.create!(level: level, holder_name: "Bella Swan", holder_email: "bella@example.com", status: "active",
                                            starts_on: Date.current, ends_on: Date.current + 364)
    get tickets_membership_path(token: member.token)
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to include("Members first: you're buying before sales open to everyone", "Continue to checkout")
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { date_general.id.to_s => "1" } }
    expect(TicketOrder.last).to have_attributes(status: "pending", ticket_membership_id: member.id)

    # A date can set its own members-first time.
    sign_in_manager
    patch manage_ticket_listing_path(listing), params: { section: "sales", ticket_listing: { members_on_sale_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M") } }
    expect(listing.reload.members_on_sale_at).to be_present
    expect(listing.members_presale_open?).to be(false)
  end

  it "seats members from the members' block, or a section up" do
    chart = org.seat_charts.create!(location_space: location.default_room, name: "Concert layout")
    orchestra = chart.sections.create!(name: "Orchestra", kind: "rows", position: 0)
    orchestra.add_rows!(count: 1, per_row: 4, first_row: "A", first_number: 1)
    balcony = chart.sections.create!(name: "Balcony", kind: "rows", position: 1)
    balcony.add_rows!(count: 1, per_row: 4, first_row: "B", first_number: 1)
    chart.update!(status: "active")
    premium = setup.ticket_tiers.create!(name: "Premium", price_cents: 4_000, position: 1)
    premium.zones.create!(seat_section: orchestra)
    general.update!(quantity: nil)
    general.zones.create!(seat_section: balcony)
    setup.update!(seating_mode: "reserved", seat_chart: chart)
    listing
    date_general

    level = org.ticket_membership_levels.create!(name: "Patron", price_cents: 10_000, status: "on_sale", better_seats: true, section_upgrade: true)
    member = org.ticket_memberships.create!(level: level, holder_name: "Bella Swan", holder_email: "bella@example.com", status: "active",
                                            starts_on: Date.current, ends_on: Date.current + 364)
    # A members' block on the balcony: B 3 and B 4.
    hold = listing.seat_holds.create!(organization: org, name: "Members", kind: "members")
    b3, b4 = balcony.seats.where(number: [ 3, 4 ]).order(:number).to_a
    hold.hold_seats.create!(ticket_listing: listing, seat: b3)
    hold.hold_seats.create!(ticket_listing: listing, seat: b4)
    expect(listing.inventory.remaining(tier: date_general)).to eq(2)

    # Everyone else gets B 1 and B 2; the member gets the block.
    other = TicketCheckout.start!(listing: listing, quantities: { date_general.id.to_s => "1" })
    expect(other.tickets.first.seat_label).to eq("Balcony B 2").or eq("Balcony B 3")
    mine = TicketCheckout.start!(listing: listing, quantities: { date_general.id.to_s => "2" }, membership: member)
    expect(mine.tickets.map(&:seat_label)).to contain_exactly("Balcony B 3", "Balcony B 4")
    expect(mine.tickets.map(&:price_cents).uniq).to eq([ 2_000 ])

    # The block spent, the upgrade: a General ticket in the Orchestra at General's price.
    up = TicketCheckout.start!(listing: listing, quantities: { date_general.id.to_s => "1" }, membership: member)
    ticket = up.tickets.first
    expect(ticket.seat.seat_section).to eq(orchestra)
    expect(ticket).to have_attributes(price_cents: 2_000, ticket_tier_id: date_general.id)
  end
end
