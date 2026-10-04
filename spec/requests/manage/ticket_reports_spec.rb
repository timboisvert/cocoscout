# frozen_string_literal: true

require "rails_helper"

# Ticketing → Reports: a period's sales on screen and as CSVs.
RSpec.describe "Ticket reports", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30))) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
  end

  it "shows this month's sales and offers the CSVs" do
    get manage_ticketing_path
    expect(response.body).to include("Reports", manage_ticket_reports_path)

    get manage_ticket_reports_path
    expect(response.body).to include("Ticket sales", "Rising Stars", "By show", "By ticket type", "Where they bought", "Fees",
                                     "$40.00", "General", "Online", "Tickets by day")

    get manage_ticket_reports_path(format: :csv)
    expect(response.body).to include("Show,Date,Tickets", "Rising Stars")

    get manage_ticket_report_buyers_path
    expect(response.content_type).to include("text/csv")
    expect(response.body).to include("Dana Scully", "dana@example.com")
  end
end
