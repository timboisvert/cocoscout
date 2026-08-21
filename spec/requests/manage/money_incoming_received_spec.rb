# frozen_string_literal: true

require "rails_helper"

# Money → Incoming is the record of the org's receivables, not only the chase
# list: payments that already arrived stay on the page as a Received history,
# each row still linking to its payment detail page.
RSpec.describe "Manage::MoneyIncoming received history", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    contractor = create(:contractor, organization: org, name: "SketchFest Chicago")
    create(:contract, :active, organization: org, production: production,
                               contractor: contractor, contractor_name: contractor.name)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "teases the most recent collections and links off to the full Received page" do
    paid = create(:contract_payment, :paid, contract: contract, direction: "incoming",
                                            amount: 250, description: "2 events, paid upfront",
                                            due_date: 1.week.ago.to_date)
    paid.update!(payment_method: "online")
    create(:contract_payment, contract: contract, direction: "incoming", amount: 100,
                              description: "Next month's rent", due_date: 3.weeks.from_now.to_date)

    get manage_money_incoming_path

    body = response.body
    expect(body).to include("Recently received")
    expect(body).to include("All received payments (1)")
    expect(body).to include(manage_money_incoming_received_path)
    expect(body).to include("2 events, paid upfront")
    expect(body).to include("Paid online")
    expect(body).to include(manage_money_incoming_payment_path(paid))
    # The pending list is untouched — still only what's owed.
    expect(body).to include("Next month&#39;s rent")
    expect(body).to include("$100.00")
  end

  it "keeps the teaser short and leaves the full book to the Received page" do
    8.times do |i|
      create(:contract_payment, :paid, contract: contract, direction: "incoming",
                                       amount: 10 + i, description: "Rent week #{i}",
                                       due_date: (8 - i).weeks.ago.to_date)
    end

    get manage_money_incoming_path
    # 6 most recent on the index…
    expect(response.body).to include("All received payments (8)")
    expect(response.body.scan("Rent week").size).to eq(6)

    # …every one of them, with the running total, on the Received page.
    get manage_money_incoming_received_path
    expect(response.body).to include("8 payments")
    expect(response.body.scan("Rent week").size).to eq(8)
    expect(response.body).to include("collected all time")
  end

  it "names the offline method a hand-recorded payment arrived by" do
    create(:contract_payment, :paid, contract: contract, direction: "incoming",
                                     amount: 80, due_date: 2.days.ago.to_date)
      .update!(payment_method: "check")

    get manage_money_incoming_path
    expect(response.body).to include("Check")
  end

  it "scopes both the teaser and the Received page to the production's own money" do
    other_production = create(:production, organization: org, production_type: "third_party")
    other_contract = create(:contract, :active, organization: org, production: other_production,
                                                contractor_name: "Someone Else")
    create(:contract_payment, :paid, contract: contract, direction: "incoming", amount: 250,
                                     description: "Ours", due_date: 1.week.ago.to_date)
    create(:contract_payment, :paid, contract: other_contract, direction: "incoming", amount: 90,
                                     description: "Theirs", due_date: 1.week.ago.to_date)

    get manage_money_production_incoming_path(production)
    expect(response.body).to include("Ours")
    expect(response.body).not_to include("Theirs")

    get manage_money_incoming_received_path(production_id: production.id)
    expect(response.body).to include("Ours")
    expect(response.body).not_to include("Theirs")
    expect(response.body).to include("$250.00 collected all time")
  end

  it "shows no Recently received section while nothing has been collected" do
    create(:contract_payment, contract: contract, direction: "incoming", amount: 100,
                              due_date: 1.week.from_now.to_date)

    get manage_money_incoming_path
    expect(response.body).not_to include("Recently received")
  end
end
