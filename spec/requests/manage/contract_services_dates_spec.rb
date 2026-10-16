# frozen_string_literal: true

require "rails_helper"

# The contract's Services step, by date (2026-10-16): the services on top with
# where each usually goes, and "Each date" below, every booked date with the
# services it gets. One date's Edit can drop a service, change its hours, or
# give it its own price, down to $0; the review adds the dates up.
RSpec.describe "Contract services, each date", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: manager) }
  let(:location) { create(:location, organization: org) }
  let(:show_time) { Time.zone.parse("2026-10-23 19:30") }
  let(:rehearsal_time) { Time.zone.parse("2026-10-22 18:00") }
  let!(:booth) do
    org.house_services.create!(name: "Booth Tech", default_price_cents: 2500, unit: "hourly", offered_on_contracts: true,
                               contract_price_cents: 3000, contract_booking_mode: "per_event")
  end
  let(:contract) do
    create(:contract, organization: org, draft_data: {
      "bookings" => [ { "location_id" => location.id, "starts_at" => rehearsal_time.iso8601, "duration" => 3, "event_type" => "rehearsal" },
                      { "location_id" => location.id, "starts_at" => show_time.iso8601, "duration" => 2, "event_type" => "show" } ]
    })
  end

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
  end

  it "lists every booked date with its own Edit, and saves a date's own price" do
    get manage_tech_contract_wizard_path(contract)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Each date", "Usually on", "Every rehearsal", "Every show", "Thu, Oct 22 · <span class=\"whitespace-nowrap\">6:00 PM", "Fri, Oct 23",
                            %(name="services[0][events][0][starts_at]" value="#{rehearsal_time.iso8601}"),
                            %(name="services[0][events][1][unit_price]"), "Tick dates to edit several at once.")

    post manage_tech_contract_wizard_path(contract), params: { services: { "0" => {
      include: "1", service_id: booth.id.to_s, name: "Booth Tech", unit: "hourly", per_event: "1", unit_price: "30", direction: "incoming", settlement: "direct",
      events: { "0" => { include: "1", starts_at: rehearsal_time.iso8601, hours: "3", unit_price: "0" },
                "1" => { include: "1", starts_at: show_time.iso8601, hours: "2", unit_price: "30.00" } }
    } } }
    line = contract.reload.draft_services.first
    expect(line["events"]).to eq([ { "starts_at" => rehearsal_time.iso8601, "hours" => 3.0, "unit_price" => 0.0 },
                                   { "starts_at" => show_time.iso8601, "hours" => 2.0 } ])

    # Back on the step, the rehearsal keeps its own $0 and the show the line's price.
    get manage_tech_contract_wizard_path(contract)
    expect(response.body).to include(%(value="0.00" aria-label="Booth Tech price this date"), %(data-own="1"))

    get manage_review_contract_wizard_path(contract)
    expect(response.body.gsub(/\s+/, " ")).to include("2 events · 5 hrs · usually $30.00/hr", "They pay us $60.00")
  end

  it "gives each booked date its own Edit" do
    get manage_tech_contract_wizard_path(contract)
    expect(response.body.scan("contract-services#openDate").size).to eq(2)
  end
end
