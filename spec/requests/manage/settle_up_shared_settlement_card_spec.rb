# frozen_string_literal: true

require "rails_helper"

# A weekly settlement's card on one of its days says it's the week's, paid
# once, and what this show adds to it; the day's "Going to the shows'
# people" counts only that (Tim, 2026-11-16).
RSpec.describe "Settle up, a week's settlement on one of its days", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) do
    create(:contract, :active, organization: org, production: production, draft_data: {
             "payment_structure" => "flat_fee",
             "payment_config" => {
               "flat_fee_direction" => "ticket_revenue_minus_fee",
               "flat_fee_amount" => 250,
               "flat_fee_basis" => "per_show",
               "flat_fee_settlement" => "weekly"
             }
           })
  end

  around { |example| travel_to(Time.zone.local(2026, 11, 16, 12)) { example.run } }

  before do
    create(:contract_payment, contract: contract, direction: "outgoing",
                              description: "Ticket revenue less $750.00 fee — week of Nov 9",
                              amount: 0, amount_tbd: true, due_date: Date.new(2026, 11, 14))
    @shows = { 12 => 600, 13 => 420, 14 => 616.28 }.to_h do |day, revenue|
      show = create(:show, production: production, date_and_time: Time.zone.local(2026, 11, day, 21))
      create(:contract_payment, contract: contract, direction: "incoming", amount: 50, show: show,
                                description: "Booth Tech — Nov #{day}, 2026",
                                settlement_method: "payout_deduction", due_date: Date.new(2026, 11, day))
      create(:show_financials, :complete, show: show, ticket_revenue: revenue, other_revenue: 0.0)
      ContractPaymentSyncService.new(show.reload).call
      [ day, show ]
    end
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "says the settlement is the week's and counts this show's part" do
    get manage_money_settle_up_day_path("2026-11-13")

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    words = doc.at_css("[data-pay-shared='#{@shows[13].id}']").text.squish
    expect(words).to eq("For the week's 3 shows, paid once. This show's part is $120.00, after $50.00 they owe for it.")
    expect(response.body).to include("After $50.00 they owe for services is kept back")
  end
end
