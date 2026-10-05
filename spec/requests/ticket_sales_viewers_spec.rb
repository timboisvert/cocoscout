# frozen_string_literal: true

require "rails_helper"

# The producer view: a theater shares a show's sales with people who aren't
# managers — the contractor automatically, team and cast by ticking, anyone
# by search or invitation — and they see sold of seats, sales and names,
# never emails, and can change nothing.
RSpec.describe "Ticket sales viewers", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }
  let(:producer) { create(:user, password: password) }
  let!(:producer_person) { create(:person, user: producer, name: "Pat Producer", email: producer.email_address) }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    create(:organization_role, :manager, user: superadmin, organization: org)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com", buyer_phone: "312-555-0100")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "shares a show with someone found by search, who then sees names but never emails, and can be cut off" do
    sign_in(superadmin)
    get manage_path
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("Visibility", manage_ticket_listing_visibility_path(listing))

    get manage_ticket_listing_visibility_path(listing)
    expect(response.body).to include("Shared with", "Nobody yet", "Add someone else")

    get manage_ticket_listing_visibility_search_path(listing, q: "Pat")
    expect(response.body).to include("Pat Producer", "Choose")

    post manage_ticket_listing_visibility_path(listing), params: { person_id: producer_person.id, share_scope: "listing" }
    expect(flash[:notice]).to include("Pat Producer can now see the sales")
    viewer = org.ticket_sales_viewers.active.sole
    expect([ viewer.user_id, viewer.scope ]).to eq([ producer.id, listing ])

    # The producer's side.
    sign_in(producer)
    get my_ticket_sales_path
    expect(response.body).to include("Ticket Sales", "Rising Stars", "2 of 60")
    get my_ticket_sale_path(listing)
    expect(response.body).to include("Dana Scully", "2 of 60", "$40.00", "Who's coming")
    expect(response.body).not_to include("dana@example.com", "312-555", "You keep", "Review refund", manage_ticket_order_path(1))

    # Another show of the production isn't shared; a different theater's never is.
    other = create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 12.days.from_now))
    get my_ticket_sale_path(other)
    expect(response).to have_http_status(:not_found)

    # Cut off.
    sign_in(superadmin)
    get manage_path
    delete manage_ticket_listing_visibility_viewer_path(listing, viewer_id: viewer.id)
    expect(viewer.reload.revoked_at).to be_present
    sign_in(producer)
    get my_ticket_sale_path(listing)
    expect(response).to have_http_status(:not_found)
    get my_ticket_sales_path
    expect(response.body).to include("No shows shared with you yet")
  end

  it "shares every date of a production with the cast ticked, and lists the production's team and cast to pick" do
    show.show_person_role_assignments.create!(assignable: producer_person, role: create(:role, production: production))
    later = create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 12.days.from_now))

    sign_in(superadmin)
    get manage_path
    get manage_ticket_listing_visibility_path(listing)
    expect(response.body).to include("Add from Rising Stars", "Pat Producer")

    post manage_ticket_listing_visibility_path(listing), params: { person_ids: [ producer_person.id ], share_scope: "production" }
    expect(org.ticket_sales_viewers.active.sole.scope).to eq(production)

    sign_in(producer)
    get my_ticket_sales_path
    expect(response.body).to include(my_ticket_sale_path(listing), my_ticket_sale_path(later))
  end

  it "lets a contract's contractor see their shows' sales unless the contract says not, with chips on My Contracts" do
    contractor = org.contractors.create!(name: "Pat Producer", person: producer_person)
    contract = create(:contract, organization: org, production: production, contractor: contractor, status: "active")
    expect(TicketSalesAccess.can_see?(producer, listing)).to be(true)

    sign_in(producer)
    get my_contracts_path
    expect(response.body).to include("2 of 60 sold", my_ticket_sale_path(listing))

    sign_in(superadmin)
    get manage_path
    get manage_ticket_listing_visibility_path(listing)
    expect(response.body).to include("Automatically", "Pat Producer")
    patch manage_ticket_listing_visibility_contract_path(listing, contract_id: contract.id), params: { shares_ticket_sales: "0" }
    expect(contract.reload.shares_ticket_sales).to be(false)
    expect(TicketSalesAccess.can_see?(producer, listing)).to be(false)
  end

  it "invites someone by email when the search finds nobody, and they accept by making an account" do
    sign_in(superadmin)
    get manage_path
    get manage_ticket_listing_visibility_search_path(listing, q: "sam@example.com")
    expect(response.body).to include("Nobody on CocoScout matches", 'value="sam@example.com"')

    expect {
      post manage_ticket_listing_visibility_invite_path(listing), params: { email: "sam@example.com", name: "Sam Producer", share_scope: "listing" }
    }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    viewer = org.ticket_sales_viewers.pending_invites.sole
    expect(viewer.invited_name).to eq("Sam Producer")

    get signout_path
    get ticket_sales_invitation_path(token: viewer.invitation_token)
    expect(response.body).to include("sharing ticket sales with you", "Make my account")
    post ticket_sales_invitation_accept_path(token: viewer.invitation_token), params: { password: password }
    expect(response).to redirect_to(my_ticket_sales_path)
    expect(viewer.reload.user).to be_present
    expect(viewer.user.person.name).to eq("Sam Producer")
    follow_redirect!
    expect(response.body).to include("Rising Stars")
  end

  it "shares every date from the production's own Visibility page" do
    sign_in(superadmin)
    get manage_path
    get manage_production_ticketing_path(production)
    expect(response.body).to include("Visibility", manage_production_ticketing_visibility_path(production))

    get manage_production_ticketing_visibility_path(production)
    expect(response.body).to include("every date of Rising Stars", "Add from Rising Stars")
    expect(response.body).not_to include("What they see")

    post manage_production_ticketing_visibility_path(production), params: { person_id: producer_person.id }
    expect(org.ticket_sales_viewers.active.sole.scope).to eq(production)
    get manage_production_ticketing_visibility_path(production)
    expect(response.body).to include("Pat Producer", "Rising Stars, every date")

    # Another theater's production reaches nothing.
    other = create(:production, organization: create(:organization, :pro))
    get manage_production_ticketing_visibility_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it "sends a producer who asked for it a morning note on their shows" do
    org.ticket_sales_viewers.create!(user: producer, scope: production, granted_by: superadmin, daily_email: true)
    expect { TicketingDailyNoticesJob.perform_now(Date.current) }.to have_enqueued_job(ActionMailer::MailDeliveryJob).at_least(:once)

    sign_in(producer)
    patch my_ticket_sales_daily_email_path, params: { daily_email: "0" }
    expect(org.ticket_sales_viewers.active.sole.daily_email).to be(false)
  end

  # A producer who sees sales only through their contract has no share row;
  # asking for the daily note makes one for each of their productions.
  it "lets a contract-only producer ask for the morning note" do
    contractor = create(:contractor, organization: org, person: producer_person, email: producer_person.email)
    create(:contract, organization: org, production: production, contractor: contractor, status: :active, shares_ticket_sales: true)
    sign_in(producer)
    expect(org.ticket_sales_viewers.count).to eq(0)
    patch my_ticket_sales_daily_email_path, params: { daily_email: "1" }
    viewer = org.ticket_sales_viewers.active.sole
    expect(viewer.scope).to eq(production)
    expect(viewer.user).to eq(producer)
    expect(viewer.daily_email).to be(true)
  end
end
