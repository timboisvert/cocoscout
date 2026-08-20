# frozen_string_literal: true

require "rails_helper"

# A minus-fee settlement waiting on ticket sales used to read "TBD", which is
# only half true: the remainder we hand back is unknown, but our fee is ours
# whatever the night sells (a night that sells under it becomes a shortfall they
# owe us). The row names the money we're sure of.
RSpec.describe "Manage::Contracts settlement amount before ticket sales", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, draft_data: {
             "payment_structure" => "flat_fee",
             "payment_config" => {
               "flat_fee_direction" => "ticket_revenue_minus_fee",
               "flat_fee_amount" => 300,
               "flat_fee_basis" => "per_show",
               "flat_fee_settlement" => "per_event"
             }
           })
  end
  let!(:rental) { create(:space_rental, contract: contract, starts_at: 3.weeks.from_now.change(hour: 18)) }
  let!(:show) { create(:show, production: production, space_rental: rental, date_and_time: 3.weeks.from_now.change(hour: 18)) }
  let!(:settlement) do
    create(:contract_payment, contract: contract, direction: "outgoing", show: show,
                              description: "Ticket revenue less $300.00 fee",
                              amount: 0, amount_tbd: true, due_date: 3.weeks.from_now.to_date)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "names our fee instead of TBD, and still says the settlement waits on ticket sales" do
    get manage_contract_path(contract)

    body = response.body
    expect(body).to include("$300.00")
    expect(body).to include("the rest of ticket sales goes back to them")
    expect(body).to include("Awaiting ticket sales")
    expect(body).not_to include("TBD")
  end

  it "adds services deducted from the settlement to what we're keeping" do
    create(:contract_payment, contract: contract, direction: "incoming", amount: 50,
                              description: "Booth Tech", settlement_method: "payout_deduction",
                              due_date: 3.weeks.from_now.to_date)

    get manage_contract_path(contract)

    body = response.body
    expect(body).to include("$350.00")
    expect(body).to include("our $300.00 fee + $50.00 services")
  end

  it "says what comes off first on the show payout page, where the figure is what we owe" do
    get manage_money_show_payout_path(show)

    body = response.body
    # The number there is money OUT — the fee can't be the headline, but it can
    # say what the remainder is waiting behind.
    expect(body).to include("TBD")
    expect(body).to include("after our $300.00 fee")
  end

  it "tells the contractor what comes off their remainder" do
    contractor_user = create(:user, password: password)
    person = create(:person, user: contractor_user, email: contractor_user.email_address)
    contract.update!(contractor: create(:contractor, organization: org, person: person, email: person.email))
    post handle_signin_path, params: { email_address: contractor_user.email_address, password: password }

    get my_contracts_path

    body = response.body
    expect(body).to include("TBD after the $300.00 fee")
    expect(body).not_to include("$TBD")
  end

  it "leaves a revenue split as TBD — nothing about it is known yet" do
    contract.update!(draft_data: contract.draft_data.merge(
      "payment_structure" => "revenue_share",
      "payment_config" => { "revenue_our_share" => 20, "revenue_their_share" => 80, "revenue_settlement" => "per_event" }
    ))

    get manage_contract_path(contract)

    expect(response.body).to include("TBD")
  end
end
