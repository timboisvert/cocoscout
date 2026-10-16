# frozen_string_literal: true

require "rails_helper"

# Financials' second screen, Review the dates (2026-10-16): every booked date
# with its kind, terms and cost, each editable for that date alone, down to $0,
# or several ticked together. Replaces "Review your schedule".
RSpec.describe "Contract wizard: Review the dates", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:location) { create(:location, organization: org, name: "Main Stage") }
  let(:show_times) { [ Time.zone.parse("2026-10-23 19:30"), Time.zone.parse("2026-10-24 19:30") ] }
  let(:rehearsal_time) { Time.zone.parse("2026-10-22 18:00") }
  let(:contract) do
    create(:contract, organization: org, draft_data: {
      "bookings" => show_times.map { |t| booking(t, "show", 2) } + [ booking(rehearsal_time, "rehearsal", 3) ],
      "payment_structure" => "revenue_share",
      "payment_config" => { "who_sells_tickets" => "org", "settlement_basis" => "revenue_share", "revenue_our_share" => 30,
                            "revenue_settlement" => "monthly",
                            "event_rates" => [ { "event_type" => "rehearsal", "unit" => "per_event", "amount" => 50.0,
                                                 "direction" => "incoming", "settlement" => "direct" } ] }
    })
  end

  def booking(time, type, hours)
    { "location_id" => location.id, "starts_at" => time.iso8601, "duration" => hours, "event_type" => type }
  end

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def page
    get manage_review_dates_contract_wizard_path(contract)
    response.body.gsub(/\s+/, " ")
  end

  it "lists every date with its kind, place, terms and cost" do
    html = page
    expect(response).to have_http_status(:ok)
    expect(html).to include("Review the dates", "3 dates booked", "Oct 22 to Oct 24, 2026 · 1 rehearsal, 2 shows", "Change the schedule",
                            "Thu, Oct 22 · 6:00 PM", "3 hrs · Main Stage", "$50 per rehearsal", "$50.00",
                            "Revenue share", "30% of ticket sales to us", "30% of sales",
                            "Fixed charges $50.00, plus our share of sales on 2 shows", "Next: Ticketing")
  end

  it "changes one date, down to $0 with a note, and back" do
    patch manage_review_dates_contract_wizard_path(contract), params: {
      dates: [ rehearsal_time.iso8601 ], values: { "rehearsal" => "0" }, note: "Tech rehearsal, included"
    }
    expect(flash[:notice]).to eq("1 date saved.")
    expect(page).to include("$0 this rehearsal", "Usually $50 per rehearsal", "Tech rehearsal, included", "Fixed charges $0.00")

    patch manage_review_dates_contract_wizard_path(contract), params: { dates: [ rehearsal_time.iso8601 ], values: { "rehearsal" => "50" }, note: "" }
    expect(contract.reload.draft_date_terms).to be_empty
  end

  it "edits several ticked dates at once, each kind by its own field" do
    patch manage_review_dates_contract_wizard_path(contract), params: {
      dates: show_times.map(&:iso8601) + [ rehearsal_time.iso8601 ], values: { "show" => "20", "rehearsal" => "25" }, note: ""
    }
    expect(flash[:notice]).to eq("3 dates saved.")
    expect(contract.reload.draft_date_terms.values).to contain_exactly({ "share" => 20.0 }, { "share" => 20.0 }, { "amount" => 25.0 })
    expect(page).to include("20% this show", "Usually 30% to us", "$25 this rehearsal")
  end

  it "sends the old Review your schedule step on to the deal, and on from the dates" do
    get manage_schedule_preview_contract_wizard_path(contract)
    expect(response).to redirect_to(manage_payments_contract_wizard_path(contract))

    post manage_review_dates_contract_wizard_path(contract)
    expect(response).to redirect_to(manage_ticketing_contract_wizard_path(contract))
  end
end
