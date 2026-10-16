# frozen_string_literal: true

require "rails_helper"

# Change services and prices (2026-10-16): the small amend job for which
# services each date gets and what they cost. Settled dates stay exactly as
# they were, whatever is posted; the reason goes in the contract's history.
RSpec.describe "Amend: change services and prices", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: manager) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:times) { [ Time.zone.local(2026, 11, 5, 19), Time.zone.local(2026, 11, 6, 19), Time.zone.local(2026, 11, 7, 19) ] }
  let!(:booth) do
    org.house_services.create!(name: "Booth Tech", default_price_cents: 2500, unit: "hourly", offered_on_contracts: true,
                               contract_booking_mode: "per_event")
  end
  let!(:security) do
    org.house_services.create!(name: "Security", default_price_cents: 5000, unit: "flat", offered_on_contracts: true,
                               contract_booking_mode: "per_event")
  end
  let(:contract) do
    create(:contract, :active, organization: org, production: production, contractor_name: "Nuns4Fun", draft_data: {
      "services" => [ { "name" => "Booth Tech", "service_id" => booth.id, "per_event" => true, "unit" => "hourly", "unit_price" => 25.0,
                        "direction" => "incoming", "settlement" => "direct", "quantity" => 6.0,
                        "events" => times.map { |t| { "starts_at" => t.iso8601, "hours" => 2.0 } } } ]
    })
  end

  before do
    times.each do |t|
      rental = create(:space_rental, contract: contract, starts_at: t, ends_at: t + 3.hours)
      create(:show, production: production, space_rental: rental, date_and_time: t, duration_minutes: 120)
    end
    contract.bill_services!(contract.draft_services)
    # The first night's booth tech is paid: that date is settled.
    contract.contract_payments.find_by(due_date: times.first.to_date).update!(status: "paid", paid_date: Date.current)

    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
  end

  def row(starts_at, hours:, price:, on: true)
    { include: on ? "1" : "0", starts_at: starts_at.iso8601, hours: hours.to_s, unit_price: price.to_s }
  end

  it "is offered on the chooser, and shows the settled date collapsed and read-only" do
    get amend_choose_manage_contract_path(contract)
    expect(response.body).to include("Change services and prices", amend_services_manage_contract_path(contract))

    get amend_services_manage_contract_path(contract)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("1 date already settled, Nov 5.", "They stay as they are.", "Show them", "Why the change?")
    expect(html).to include(%(<input disabled type="hidden" name="services[0][events][0][starts_at]"))
  end

  it "changes the open dates, keeps the settled one, and records why" do
    post stage_amend_services_manage_contract_path(contract), params: {
      reason: "Our tech was training on Nov 6. They asked for security on closing night.",
      services: {
        "0" => { include: "1", service_id: booth.id, name: "Booth Tech", unit: "hourly", per_event: "1", unit_price: "25",
                 direction: "incoming", settlement: "direct",
                 # A crafted post for the settled night is ignored.
                 events: { "0" => row(times[0], hours: 5, price: 99), "1" => row(times[1], hours: 2, price: 0), "2" => row(times[2], hours: 2, price: 25) } },
        "1" => { include: "1", service_id: security.id, name: "Security", unit: "flat", per_event: "1", unit_price: "50",
                 direction: "incoming", settlement: "direct",
                 events: { "2" => row(times[2], hours: 1, price: 50) } }
      }
    }
    expect(response).to redirect_to(review_amend_services_manage_contract_path(contract))

    follow_redirect!
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("2 changes", "Fri, Nov 6: Booth Tech $50.00 to $0.00", "−$50.00", "Sat, Nov 7: Security added", "+$50.00",
                            "Our tech was training on Nov 6.")
    expect(html).not_to include("Nov 5: Booth Tech")

    expect {
      post apply_amend_services_manage_contract_path(contract), params: { reason: "Our tech was training on Nov 6. They asked for security on closing night." }
    }.to change { contract.contract_versions.count }.by_at_least(1)
    expect(flash[:notice]).to start_with("Services and prices changed, recorded as v")

    contract.reload
    booth_line = contract.draft_services.find { |l| l["name"] == "Booth Tech" }
    expect(booth_line["events"]).to eq([ { "starts_at" => times[0].iso8601, "hours" => 2.0 },
                                         { "starts_at" => times[1].iso8601, "hours" => 2.0, "unit_price" => 0.0 },
                                         { "starts_at" => times[2].iso8601, "hours" => 2.0 } ])
    expect(contract.draft_data).not_to have_key("services_change")
    expect(contract.contract_versions.order(:version_number).last.change_summary)
      .to eq("Changed services and prices: Our tech was training on Nov 6. They asked for security on closing night.")

    by_date = contract.contract_payments.order(:due_date).group_by(&:due_date).transform_values { |ps| ps.sum { |p| p.amount.to_f } }
    expect(by_date).to eq(times[0].to_date => 50.0, times[2].to_date => 100.0) # Nov 6 is $0 now; Nov 7 adds security
    expect(contract.contract_payments.find_by(due_date: times.first.to_date)).to be_status_paid
  end

  it "locks the settled date in the deal amendment's Services step too, and keeps what it had" do
    get amend_ticketing_tech_manage_contract_path(contract)
    expect(response.body).to include("1 date already settled, Nov 5.")

    post save_amend_ticketing_tech_manage_contract_path(contract), params: { services: { "0" => {
      include: "1", service_id: booth.id, name: "Booth Tech", unit: "hourly", per_event: "1", unit_price: "25", direction: "incoming", settlement: "direct",
      events: { "2" => row(times[2], hours: 3, price: 25) }
    } } }
    events = contract.reload.amend_data["services"].first["events"]
    expect(events.map { |e| [ Time.zone.parse(e["starts_at"]), e["hours"] ] }).to eq([ [ times[0], 2.0 ], [ times[2], 3.0 ] ])
  end

  it "keeps the settled date at the price it was billed at when the usual price changes" do
    post stage_amend_services_manage_contract_path(contract), params: { services: { "0" => {
      include: "1", service_id: booth.id, name: "Booth Tech", unit: "hourly", per_event: "1", unit_price: "20", direction: "incoming", settlement: "direct",
      events: { "1" => row(times[1], hours: 2, price: 20), "2" => row(times[2], hours: 2, price: 20) }
    } } }
    follow_redirect!
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Nov 6 and Nov 7: Booth Tech $50.00 to $40.00 each")
    expect(html).not_to include("Nov 5")

    post apply_amend_services_manage_contract_path(contract)
    events = contract.reload.draft_services.first["events"]
    expect(events.first).to eq("starts_at" => times[0].iso8601, "hours" => 2.0, "unit_price" => 25.0)
    expect(Contract.service_line_total(contract.draft_services.first)).to eq(130.0)
  end

  it "says so when nothing changed" do
    post stage_amend_services_manage_contract_path(contract), params: { services: { "0" => {
      include: "1", service_id: booth.id, name: "Booth Tech", unit: "hourly", per_event: "1", unit_price: "25", direction: "incoming", settlement: "direct",
      events: { "1" => row(times[1], hours: 2, price: 25), "2" => row(times[2], hours: 2, price: 25) }
    } } }
    follow_redirect!
    expect(response.body).to include("These are the services and prices the contract already has.")

    post apply_amend_services_manage_contract_path(contract)
    expect(flash[:notice]).to eq("No changes to services or prices.")
  end
end
