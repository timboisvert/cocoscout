# frozen_string_literal: true

require "rails_helper"

# The event page's Contract box (2026-10-16): the date's services and payment
# from its contract, with View Contract and Change services and prices. And on
# Scheduling, a contract service dropped for one show says it's still billed.
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

  it "shows the date's services and payment, and the way to change them" do
    get manage_show_path(production, show)
    html = response.body.gsub(/\s+/, " ")
    payment = contract.contract_payments.sole
    expect(html).to include("Nuns4Fun", "Services for this date", "Booth Tech, 2 hrs", "$50.00", "This date&#39;s payment",
                            "They pay us. Due #{at.strftime('%b %-d')}.", "See the payment", manage_money_incoming_payment_path(payment),
                            "View Contract", "Change services and prices", amend_services_manage_contract_path(contract))
  end

  it "says on Scheduling that a contract service dropped for this show is still billed" do
    patch manage_staffing_show_service_path(show, service_id: booth.id, needed: "0")
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Not needed for this show, but Nuns4Fun&#39;s contract still bills it.", amend_services_manage_contract_path(contract))
  end
end
