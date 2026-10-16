# frozen_string_literal: true

require "rails_helper"

# Change the deal → Review the dates (2026-10-16): the same screen as a new
# contract's, after signing. One show's split or one date's fee changes here,
# shows on Confirm, and lands on the show when the amendment applies.
RSpec.describe "Amend: Review the dates", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:location) { create(:location, organization: org, name: "Main Stage") }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:times) { [ Time.zone.local(2026, 11, 6, 19, 30), Time.zone.local(2026, 11, 7, 19, 30) ] }
  let(:contract) do
    create(:contract, :active, organization: org, production: production, contractor_name: "Weens", draft_data: {
      "payment_structure" => "revenue_share",
      "payment_config" => { "who_sells_tickets" => "org", "settlement_basis" => "revenue_share", "revenue_our_share" => 30,
                            "revenue_settlement" => "monthly" }
    })
  end
  let!(:shows) do
    times.map do |t|
      rental = create(:space_rental, contract: contract, location: location, starts_at: t, ends_at: t + 2.hours)
      create(:show, production: production, space_rental: rental, date_and_time: t, duration_minutes: 120)
    end
  end

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def page
    get amend_review_dates_manage_contract_path(contract)
    response.body.gsub(/\s+/, " ")
  end

  it "lists the contract's dates with the deal's terms, and the shows' own" do
    shows.first.update!(contract_terms: { "share" => 10.0 })
    html = page
    expect(response).to have_http_status(:ok)
    expect(html).to include("Review the dates", "2 dates booked", "Fri, Nov 6", "2 hrs · Main Stage",
                            "10% this show", "Usually 30% to us", "30% of ticket sales to us", "Next: Ticketing &amp; Services")
  end

  it "changes one show's share, shows it on Confirm, and stamps it on the show" do
    patch amend_review_dates_manage_contract_path(contract), params: {
      dates: [ times.first.iso8601 ], values: { "show" => "0" }, note: "Benefit night"
    }
    expect(flash[:notice]).to eq("1 date saved.")
    expect(page).to include("0% this show", "Benefit night")

    post amend_review_dates_manage_contract_path(contract)
    expect(response).to redirect_to(amend_ticketing_tech_manage_contract_path(contract))

    get amend_review_manage_contract_path(contract)
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Dates with their own terms", "Fri, Nov 6 · Show", "0% this show", "Benefit night")

    # The deal's own night-by-night settlements, as Financials staged them.
    payments = times.map { |t| { "description" => "#{t.strftime('%b %-d')} — 70% to them", "amount" => 0, "amount_tbd" => true,
                                 "direction" => "outgoing", "source" => "Revenue share", "due_date" => t.to_date.to_s } }
    contract.reload.update_amend_data(contract.amend_data.merge("payment_structure" => "revenue_share",
                                                         "payment_config" => contract.draft_payment_config.merge("revenue_settlement" => "same_day"),
                                                         "payments" => payments))

    post apply_amendments_manage_contract_path(contract)
    expect(shows.first.reload.contract_terms).to eq("share" => 0.0, "note" => "Benefit night")
    expect(contract.reload.contract_payments.order(:due_date).pluck(:description)).to eq([ "Nov 6 — 100% to them", "Nov 7 — 70% to them" ])
    expect(shows.last.reload.contract_terms).to eq({})
    expect(contract.reload.contract_versions.order(:version_number).last.change_summary).to include("date terms")
  end

  it "keeps a settled date's terms: no Edit, and a crafted save is ignored" do
    create(:contract_payment, :paid, contract: contract, description: "Nov 6 settlement", amount: 100, direction: "outgoing",
                                     due_date: times.first.to_date, show: shows.first)
    html = page
    expect(html).to include("Settled")
    expect(html.scan("click->modal#open").size).to eq(1 + 1) # the open date's Edit, and Edit the ticked dates

    patch amend_review_dates_manage_contract_path(contract), params: { dates: [ times.first.iso8601 ], values: { "show" => "0" }, note: "" }
    expect(flash[:notice]).to eq("Nothing to change on those dates.")
  end

  it "bills a per-event deal's date at its own fee" do
    contract.update!(draft_data: { "payment_structure" => "per_event",
                                   "payment_config" => { "settlement_basis" => "flat", "per_event_amount" => 200 } })
    payments = times.map { |t| { "description" => "#{t.strftime('%b %-d')} event", "amount" => 200, "direction" => "incoming",
                                 "source" => "Per event", "due_date" => t.to_date.to_s, "event_date" => t.iso8601 } }
    contract.update_amend_data("payment_structure" => "per_event", "payment_config" => contract.draft_payment_config, "payments" => payments)

    patch amend_review_dates_manage_contract_path(contract), params: { dates: [ times.last.iso8601 ], values: { "show" => "0" }, note: "" }
    post apply_amendments_manage_contract_path(contract)

    expect(contract.reload.contract_payments.map { |p| [ p.due_date, p.amount.to_f ] }).to eq([ [ times.first.to_date, 200.0 ] ])
    expect(shows.last.reload.contract_terms).to eq("amount" => 0.0)
  end
end
