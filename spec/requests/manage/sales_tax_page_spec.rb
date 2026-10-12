# frozen_string_literal: true

require "rails_helper"

# The Sales tax page (Tim, 2026-10-12): what's collected, what's set aside,
# marking a period paid, and how filing works; plus the setting that keeps
# the tax set aside.
RSpec.describe "Sales tax page", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner, stripe_account_id: "acct_sg", payouts_enabled: true) }
  let(:listing) do
    create(:ticket_listing, organization: org,
                            show: create(:show, production: create(:production, organization: org), date_and_time: Time.zone.local(2026, 10, 10, 19, 30)))
  end
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    TicketingProfile.for(org).update!(enabled: true)
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    org.update_column(:sales_tax_set_aside_since, Date.new(2026, 10, 1))
    travel_to(Time.zone.local(2026, 10, 1, 12)) do
      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
      order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com")
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_sale")
    end
    travel_to(Time.zone.local(2026, 10, 13, 12))
    TicketMoneyReleaseJob.perform_now
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  after { travel_back }

  it "shows what's set aside, marks the month paid, and undoes it" do
    get manage_ticket_taxes_path(period: "2026-10")
    expect(response.body).to include("Set aside for sales tax", "$4.10", "October 2026: <span", "How to file and pay", "Mark paid")
    expect(response.body).not_to include("In Chicago")
    get manage_ticket_balance_path
    expect(response.body).to include("Set aside for sales tax: <span class=\"tabular-nums\">$4.10</span>")

    post manage_ticket_tax_remittances_path(period: "2026-10", basis: "sale", kind: "all"),
         params: { remittance: { tax_name: "Sales tax", rate_bps: 1025, basis: "sale", period_start: "2026-10-01", period_end: "2026-10-31",
                                 amount: "4.10", paid_on: "2026-10-13", reference: "CHI-123" } }
    expect(response).to redirect_to(manage_ticket_taxes_path(period: "2026-10", basis: "sale", kind: "all"))
    expect(flash[:notice]).to include("Sales tax for October 2026 marked paid")
    remittance = org.sales_tax_remittances.sole
    expect(remittance).to have_attributes(amount_cents: 410, reference: "CHI-123", recorded_by_id: owner.id)
    expect(SalesTaxSetAside.cents(org)).to eq(0)

    get manage_ticket_taxes_path(period: "2026-10")
    expect(response.body).to include("October 2026: $4.10 collected, marked paid", "Paid Oct 13", "CHI-123", "Undo marking it paid?")

    delete manage_ticket_tax_remittance_path(remittance, period: "2026-10")
    expect(org.sales_tax_remittances).to be_empty
    expect(SalesTaxSetAside.cents(org)).to eq(410)
  end

  it "says what Chicago's taxes are, and flags a 10.25% ticket rate" do
    create(:location, organization: org, city: "Chicago", state: "IL")

    get manage_ticket_taxes_path(period: "2026-10")
    expect(response.body).to include("In Chicago", "City of Chicago Amusement Tax", "Cook County Amusement Tax",
                                      "That's Chicago's sales tax rate, not its amusement tax")
  end

  it "turns setting aside off and on in Ticketing settings" do
    get manage_ticketing_settings_section_path(section: "tax")
    expect(response.body).to include("Keep sales tax set aside", "Set aside since October 1, 2026")

    patch manage_ticketing_settings_tax_path, params: { tax: { name: "Sales tax", percent: "10.25", mode: "added", set_aside: "0" } }
    expect(org.reload.sales_tax_set_aside_since).to be_nil
    get manage_ticket_taxes_path(period: "2026-10")
    expect(response.body).to include("Sales tax isn't set aside")

    patch manage_ticketing_settings_tax_path, params: { tax: { name: "Sales tax", percent: "10.25", mode: "added", set_aside: "1" } }
    expect(org.reload.sales_tax_set_aside_since).to eq(Date.new(2026, 10, 13))
  end

  it "never touches another organization's payments" do
    other = create(:organization, :pro)
    theirs = other.sales_tax_remittances.create!(tax_name: "Sales tax", rate_bps: 1025, basis: "sale", period_start: Date.new(2026, 10, 1),
                                                 period_end: Date.new(2026, 10, 31), amount_cents: 100, paid_on: Date.new(2026, 10, 13))

    delete manage_ticket_tax_remittance_path(theirs)
    expect(response).to have_http_status(:not_found)
    expect(theirs.reload).to be_persisted
  end
end
