# frozen_string_literal: true

require "rails_helper"

# A contract out for signature has no bookings or payment rows yet: its dates
# and payments are in its draft until it's signed. The contract page shows
# them anyway (Tim, 2026-11-23).
RSpec.describe "Contract page: dates and payments out for signature", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org, name: "Main Hall") }
  let!(:contract) do
    create(:contract, organization: org, contractor_name: "Sound Co", contractor_email: "sound@example.com",
                      signing_mode: "esign", signing_state: "out_for_signature",
                      draft_data: {
                        "bookings" => [
                          { "starts_at" => "2027-08-09T18:00:00-05:00", "duration" => "2", "location_id" => location.id.to_s, "event_type" => "rehearsal" },
                          { "starts_at" => "2027-08-20T19:30:00-05:00", "duration" => "2", "location_id" => location.id.to_s, "event_type" => "show" }
                        ],
                        "payment_config" => {
                          "event_rates" => [ { "event_type" => "rehearsal", "unit" => "hourly", "amount" => 25.0,
                                               "direction" => "incoming", "settlement" => "direct" } ]
                        },
                        "payments" => [
                          { "description" => "Deposit", "amount" => 500, "due_date" => "2027-08-01", "direction" => "incoming" },
                          { "description" => "Rental fee", "amount" => 300, "due_date" => "2027-08-20", "direction" => "incoming" }
                        ]
                      })
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "lists the draft's dates and payments" do
    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("The dates and payments sent to Sound Co to sign.")
    expect(body).to include("Entire venue at Main Hall")
    expect(body).to include("Deposit")
    expect(body).to include("$500.00")
    expect(body).to include("Rental fee: due Aug 20.")
    expect(body).not_to include("No dates or payments yet.")
  end

  it "charges each rehearsal at its own rate, as signing will" do
    charges = contract.draft_event_rate_charges

    expect(charges.map { |c| c.values_at("description", "amount", "due_date") })
      .to eq([ [ "Rehearsal — Aug 9, 2027", 50.0, "2027-08-09" ] ])

    get manage_contract_path(contract)
    expect(response.body).to include("Rehearsal: due Aug 9.")
    expect(response.body).to include("$50.00")
  end

  it "puts the rehearsal charges on the document to sign" do
    grid = contract.send(:license_schedule_html)
    expect(grid).to include("<td>$50.00</td>")
    expect(grid).to include("Rehearsal charges ($50.00 in all) are due on the day of each rehearsal.")

    terms = contract.send(:deal_terms_html)
    expect(terms).to include("<td>Rehearsal — Aug 9, 2027</td><td>They pay us</td><td>$50.00</td><td>2027-08-09</td>")
  end
end
