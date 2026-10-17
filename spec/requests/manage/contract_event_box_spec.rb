# frozen_string_literal: true

require "rails_helper"

# The event page's Contract box (2026-10-16; read the producer's way,
# 2026-10-17): the date's terms, what they get and when it's known, each
# service and how it's settled, with View Contract and Change services and
# prices. And on Scheduling, a contract service dropped for one show says
# it's still billed.
RSpec.describe "A contracted date's Contract box", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:week_start) { Date.current.next_week.beginning_of_week }
  let(:at) { (week_start + 2).in_time_zone.change(hour: 18) }
  let!(:booth_role) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific) }
  let!(:booth) { org.house_services.create!(name: "Booth Tech", unit: "hourly").tap { |s| s.house_roles << booth_role } }
  let(:contract) do
    create(:contract, :active, organization: org, production: production, contractor_name: "Nuns4Fun", draft_data: {
      "services" => [ { "name" => "Booth Tech", "service_id" => booth.id, "per_event" => true, "unit" => "hourly", "unit_price" => 25.0,
                        "direction" => "incoming", "settlement" => "direct", "quantity" => 2.0,
                        "events" => [ { "starts_at" => at.iso8601, "hours" => 2.0 } ] } ]
    })
  end
  let!(:show) do
    rental = create(:space_rental, contract: contract, starts_at: at, ends_at: at + 3.hours)
    create(:show, production: production, space_rental: rental, date_and_time: at, duration_minutes: 120, event_type: "rehearsal")
  end

  before do
    contract.bill_services!(contract.draft_services)
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "shows the date's services, each with how it's settled, and the way to change them" do
    get manage_show_path(production, show)
    html = response.body.gsub(/\s+/, " ")
    payment = contract.contract_payments.sole
    expect(html).to include("Nuns4Fun", "Services this date", "Booth Tech, 2 hrs", "$50.00", "They pay us. Due #{at.strftime('%b %-d')}.",
                            "See the payment", manage_money_incoming_payment_path(payment),
                            "View Contract", "Change services and prices", amend_services_manage_contract_path(contract))
    expect(html).not_to include("Services for this date", "This date&#39;s payment", "What they get")
    expect(html.scan("Booth Tech").size).to eq(1)
  end

  # Tim, 2026-10-17 (Dan Feltey's night): a producer on a revenue share
  # reads that the amount waits on ticket sales, and that the booth tech
  # comes out of it. Never "they pay us" or a due date for that service.
  it "reads a revenue share as what they get, with the services that come out of it" do
    night = (week_start + 4).in_time_zone.change(hour: 20)
    deal = create(:contract, :active, organization: org, production: production, contractor_name: "Dan Feltey", draft_data: {
      "services" => [ { "name" => "Booth Tech", "service_id" => booth.id, "per_event" => true, "unit" => "hourly", "unit_price" => 25.0,
                        "direction" => "incoming", "settlement" => "payout_deduction", "quantity" => 2.0,
                        "events" => [ { "starts_at" => night.iso8601, "hours" => 2.0 } ] } ]
    })
    rental = create(:space_rental, contract: deal, starts_at: night, ends_at: night + 3.hours)
    gig = create(:show, production: production, space_rental: rental, date_and_time: night, duration_minutes: 120, event_type: "show")
    deal.contract_payments.create!(description: "#{night.strftime('%b %-d')} — 50% to them", amount: 0, amount_tbd: true, direction: "outgoing", due_date: night.to_date, show: gig)
    deal.contract_payments.create!(description: "Booth Tech — #{night.strftime('%b %-d, %Y')}", amount: 50, direction: "incoming",
                                   settlement_method: "payout_deduction", due_date: night.to_date, show: gig)

    get manage_show_path(production, gig)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Dan Feltey", "What they get", "TBD", "Known once ticket sales are final.", "Less $50.00 for the services below.",
                            "Services this date", "Booth Tech, 2 hrs", "Out of their share.")
    expect(html).not_to include("They pay us", "We pay them", "night", "Due #{night.strftime('%b %-d')}")
    expect(html.scan("Booth Tech").size).to eq(1)
  end

  it "says on Scheduling that a contract service dropped for this show is still billed" do
    patch manage_staffing_show_service_path(show, service_id: booth.id, needed: "0")
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Not needed for this show, but Nuns4Fun&#39;s contract still bills it.", amend_services_manage_contract_path(contract))
  end
end
