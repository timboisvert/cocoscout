# frozen_string_literal: true

require "rails_helper"

# Phase 6: for a Case-2 contract (the contractor sells their own tickets on a
# revenue split), the contractor self-reports ticket sales from /my/contracts.
# We trust the numbers, write them to ShowFinancials, and let the sync generate
# the incoming payment for our cut.
RSpec.describe "My::Contracts report sales", type: :request do
  let(:password) { "Password123!" }
  let!(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user) }
  let!(:org) { create(:organization, :pro) }
  let!(:contractor) { create(:contractor, organization: org, person: person) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }

  # Case 2: they sell, revenue split, our cut is 30%.
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor,
      contractor_name: contractor.name, contractor_email: contractor.email,
      draft_data: {
        "payment_structure" => "revenue_share",
        "payment_config" => {
          "who_sells_tickets" => "contractor",
          "settlement_basis" => "revenue_share",
          "revenue_our_share" => 30,
          "revenue_their_share" => 70,
          "revenue_settlement" => "per_event"
        }
      })
  end

  let!(:location) { create(:location, organization: org) }
  let!(:rental) do
    create(:space_rental, contract: contract, location: location,
      starts_at: 1.month.from_now.change(hour: 19), ends_at: 1.month.from_now.change(hour: 22))
  end
  let!(:show) do
    production.shows.create!(date_and_time: 1.month.from_now.change(hour: 19), duration_minutes: 120,
      location: location, space_rental: rental)
  end
  # Activation would normally generate the per-event settlement payment; create it
  # directly so the sync has something to settle into.
  let!(:payment) do
    create(:contract_payment, :revenue_share_tbd, contract: contract, direction: "incoming",
      show_id: show.id, due_date: show.date_and_time)
  end

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "shows the report-sales affordance on the contract index" do
    get my_contracts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Report ticket sales")
  end

  it "renders the report form for a Case-2 contract" do
    get my_report_contract_sales_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("You sell the tickets")
  end

  it "writes the reported sales to ShowFinancials and marks them contractor-reported" do
    patch my_report_contract_sales_path(contract), params: {
      financials: { show.id.to_s => { ticket_count: "42", ticket_revenue: "840.00" } }
    }

    expect(response).to redirect_to(my_contracts_path)

    financials = show.reload.show_financials
    expect(financials.ticket_count).to eq(42)
    expect(financials.ticket_revenue).to eq(840.00)
    expect(financials).to be_contractor_reported
    expect(financials).to be_data_confirmed
  end

  it "produces our incoming cut as a contract payment after reporting" do
    patch my_report_contract_sales_path(contract), params: {
      financials: { show.id.to_s => { ticket_count: "42", ticket_revenue: "840.00" } }
    }

    # 30% of 840 = 252 owed to us on the per-event payment for this show.
    payment = contract.reload.contract_payments.find_by(show_id: show.id)
    expect(payment).to be_present
    expect(payment.direction).to eq("incoming")
    expect(payment.amount.to_f).to eq(252.00)
  end

  it "refuses to report on a contract the person does not hold" do
    other_contract = create(:contract, :active, organization: org, production: production,
      draft_data: contract.draft_data)

    get my_report_contract_sales_path(other_contract)

    expect(response).to redirect_to(my_contracts_path)
  end

  it "redirects when the contract isn't a contractor-sells revenue split" do
    flat = create(:contract, :active, organization: org, production: production, contractor: contractor,
      draft_data: { "payment_structure" => "flat_fee", "payment_config" => { "who_sells_tickets" => nil } })

    get my_report_contract_sales_path(flat)

    expect(response).to redirect_to(my_contracts_path)
    follow_redirect!
    expect(response.body).to include("nothing to report")
  end
end
