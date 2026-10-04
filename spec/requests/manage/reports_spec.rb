# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Reports", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the reports index" do
    get manage_reports_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reports")
  end

  it "renders each built report without error" do
    [
      manage_report_revenue_by_production_path,
      manage_report_revenue_over_time_path,
      manage_report_events_summary_path,
      manage_report_cast_participation_path,
      manage_report_payouts_summary_path,
      manage_report_course_revenue_path
    ].each do |path|
      get path
      expect(response).to have_http_status(:ok), "expected #{path} to render"
    end
  end

  it "downloads each report as a CSV spreadsheet" do
    [
      manage_report_revenue_by_production_path(format: :csv),
      manage_report_revenue_over_time_path(format: :csv),
      manage_report_events_summary_path(format: :csv),
      manage_report_cast_participation_path(format: :csv),
      manage_report_payouts_summary_path(format: :csv),
      manage_report_course_revenue_path(format: :csv)
    ].each do |path|
      get path
      expect(response).to have_http_status(:ok), "expected #{path} to download"
      expect(response.media_type).to eq("text/csv"), "expected #{path} to be CSV"
      expect(response.headers["Content-Disposition"]).to include(".csv")
    end
  end

  it "presents Payouts as its own section and drops the coming-soon reports" do
    get manage_reports_path
    expect(response.body).to include("Payouts")
    expect(response.body).not_to include("Coming soon")
    expect(response.body).not_to include("Availability Response Rates")
  end

  describe "ticketing reports" do
    let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }

    before do
      create(:organization_role, :manager, user: superadmin, organization: org)
      TicketingProfile.for(org).update!(enabled: true)
      listing = create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)))
      tier = listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
      order = TicketCheckout.start!(listing: listing, quantities: { tier.id.to_s => "2" })
      order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com")
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
    end

    it "live in the Reports section, for superadmins while ticketing is experimental" do
      get manage_reports_path
      expect(response.body).not_to include("Ticket Sales by Show")
      get manage_report_ticket_sales_by_show_path
      expect(response).to redirect_to(manage_reports_path)

      post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
      post set_organization_path(id: org.id)
      get manage_reports_path
      expect(response.body).to include("Ticketing", "Ticket Sales by Show", "Ticket Buyers", "Taxes Collected on Tickets", manage_ticket_taxes_path)

      get manage_report_ticket_sales_by_show_path
      expect(response.body).to include("Ticket Sales by Show", "Count each sale by", "Held for the show", "$40.00", "Download spreadsheet")
      get manage_report_ticket_sales_by_type_path(basis: "event")
      expect(response.body).to include("General", 'value="event" selected="selected"')
      get manage_report_ticket_sales_by_channel_path
      expect(response.body).to include("Online")
      get manage_report_ticket_buyers_path
      expect(response.body).to include("Dana Scully", "dana@example.com")

      get manage_report_ticket_sales_by_show_path(format: :csv, basis: "event")
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Show,Tickets,Comps")

      # The Ticketing home points at Reports.
      get manage_ticketing_path
      expect(response.body).to include(manage_reports_path)
    end
  end

  it "gates reports behind the Pro plan" do
    free_owner = create(:user, password: password)
    free_org = create(:organization, owner: free_owner)
    create(:organization_role, :manager, user: free_owner, organization: free_org)
    post handle_signin_path, params: { email_address: free_owner.email_address, password: password }

    get manage_reports_path
    expect(response).to have_http_status(:payment_required)
    expect(response.body).to include("Reports")
  end
end
