# frozen_string_literal: true

require "rails_helper"

# A revenue share's minimum guarantee shows downstream, not just on the wizard
# (Tim, 2026-11-20: "all the way downstream it needs to work"): the contract
# page, the production's Financials, the contracts list, and Settle up.
RSpec.describe "Minimum guarantee pages", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, production_type: "third_party", name: "Improv Night") }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  def contract_with(scope:, amount:)
    contract = create(:contract, :active, organization: org, production: production, contractor_name: "Improv Night",
                                          draft_data: {
                                            "payment_structure" => "revenue_share",
                                            "payment_config" => {
                                              "who_sells_tickets" => "org", "settlement_basis" => "revenue_share",
                                              "revenue_our_share" => 50, "revenue_their_share" => 50, "revenue_settlement" => "per_event",
                                              "revenue_has_guarantee" => true, "revenue_guarantee_amount" => amount.to_s,
                                              "revenue_guarantee_scope" => scope
                                            }
                                          })
    shows = [ 600.0, 1300.0 ].each_with_index.map do |revenue, i|
      show = create(:show, production: production, date_and_time: 3.days.ago.change(hour: 19) + i.days)
      create(:contract_payment, :revenue_share_tbd, contract: contract, show: show, direction: "outgoing",
                                                    due_date: show.date_and_time.to_date, description: "#{show.date_and_time.strftime('%b %-d')} — 50% to them")
      create(:show_financials, :complete, show: show, ticket_revenue: revenue, other_revenue: 0.0)
      show
    end
    [ contract, shows ]
  end

  def text = Nokogiri::HTML(response.body).text.squish

  it "shows a per-show minimum on the contract page, and the production's Financials" do
    contract, shows = contract_with(scope: "per_show", amount: 500)
    shows.each { |show| ContractPaymentSyncService.new(show).call }

    get manage_contract_path(contract)
    expect(response).to have_http_status(:ok)
    expect(text).to include("Improv Night takes home at least $500 a show.")
    expect(text).to include("Includes $200 to bring it up to the $500 minimum a show.")

    get manage_money_production_financials_path(production)
    expect(response).to have_http_status(:ok)
    expect(text).to include("at least $500 a show")
    # $500 (raised from $300) and $650 go out.
    expect(text).to include("Direct Costs $1,150.00")
  end

  it "shows the whole run's top-up on the contract page and in Settle up on the last night" do
    contract, shows = contract_with(scope: "run", amount: 1200)
    create(:contract_payment, contract: contract, description: Contract::RUN_GUARANTEE, amount: 0, amount_tbd: true,
                              direction: "outgoing", due_date: shows.last.date_and_time.to_date + 1)
    ContractPaymentSyncService.new(shows.last).call

    top_up = contract.reload.run_guarantee_payment
    expect(top_up).to have_attributes(amount: 250.0, show_id: shows.last.id)

    get manage_contract_path(contract)
    expect(text).to include("Minimum guarantee for the run")
    expect(text).to include("Their shares came to $950.00, $250.00 under the $1,200.00 minimum.")

    get manage_money_settle_up_day_path(SettlementDay.day_for(org, shows.last.date_and_time).iso8601)
    expect(response).to have_http_status(:ok)
    expect(text).to include("Minimum guarantee for the run")
  end
end
