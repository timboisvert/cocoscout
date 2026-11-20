# frozen_string_literal: true

require "rails_helper"

# A revenue share's minimum guarantee is per show or for the whole run (Tim,
# 2026-11-20). Their 50% each night: $300, $650, $200, $400.
RSpec.describe ContractRevenueGuarantee, type: :model do
  let(:organization) { create(:organization) }
  let(:nights) { [ 600.0, 1300.0, 400.0, 800.0 ] }

  def contract_with(scope:, amount: 500, settlement: "per_event", who_sells: "org")
    contract = create(:contract, :active, organization: organization,
                                          draft_data: {
                                            "payment_structure" => "revenue_share",
                                            "payment_config" => {
                                              "who_sells_tickets" => who_sells, "settlement_basis" => "revenue_share",
                                              "revenue_our_share" => 50, "revenue_their_share" => 50,
                                              "revenue_settlement" => settlement,
                                              "revenue_has_guarantee" => true, "revenue_guarantee_amount" => amount.to_s,
                                              "revenue_guarantee_scope" => scope
                                            }
                                          })
    production = create(:production, organization: organization, production_type: "third_party")
    contract.update!(production: production)
    contract
  end

  def add_shows(contract, revenues = nights, financials: true)
    revenues.each_with_index.map do |revenue, i|
      show = create(:show, production: contract.production, date_and_time: Time.zone.parse("2026-03-25 19:00") + i.days)
      create(:show_financials, :complete, show: show, ticket_revenue: revenue, other_revenue: 0.0) if financials
      show
    end
  end

  describe "per show" do
    it "settles each night as the larger of their share and the minimum" do
      contract = contract_with(scope: "per_show")
      shows = add_shows(contract)

      expect(shows.map { |show| contract.settled_share_amount([ show ]) }).to eq([ 500.0, 650.0, 500.0, 500.0 ])
      expect(contract.settled_share_amount(shows)).to eq(2150.0)
    end

    it "leaves them at least the minimum of their own sales when they sell" do
      contract = contract_with(scope: "per_show", who_sells: "contractor")
      low, high = add_shows(contract, [ 600.0, 1300.0 ])

      # Our 50% of $600 would leave them $300; we take only $100.
      expect(contract.settled_share_amount([ low ])).to eq(100.0)
      expect(contract.settled_share_amount([ high ])).to eq(650.0)
    end

    it "fills the night's settlement with the floor" do
      contract = contract_with(scope: "per_show")
      show = add_shows(contract, [ 600.0 ]).first
      payment = create(:contract_payment, :revenue_share_tbd, contract: contract, show: show, direction: "outgoing",
                                                              due_date: show.date_and_time.to_date + 1)

      ContractPaymentSyncService.new(show).call

      expect(payment.reload.amount.to_f).to eq(500.0)
      expect(contract.reload.contract_payments.where(description: Contract::RUN_GUARANTEE)).to be_empty
    end

    it "says so in the deal" do
      lines = contract_with(scope: "per_show").deal_summary
      expect(lines).to include({ label: "Minimum guarantee", value: "They take home at least $500.00 a show" })
    end
  end

  describe "for the whole run" do
    def run_payment(contract)
      create(:contract_payment, contract: contract, description: Contract::RUN_GUARANTEE, amount: 0, amount_tbd: true,
                                direction: "outgoing", due_date: Date.new(2026, 3, 29))
    end

    it "settles the nights as their share alone and keeps the top-up out of the settlements" do
      contract = contract_with(scope: "run")
      shows = add_shows(contract)
      payment = run_payment(contract)

      expect(contract.settled_share_amount(shows)).to eq(1550.0)
      expect(contract.settlement_payment?(payment)).to be false
      expect(contract.settlement_payments).not_to include(payment)
    end

    it "waits until every date's sales are in" do
      contract = contract_with(scope: "run", amount: 2000)
      shows = add_shows(contract, nights.first(3))
      add_shows(contract, [ 0 ], financials: false)
      payment = run_payment(contract)

      ContractPaymentSyncService.new(shows.first).call

      expect(payment.reload).to have_attributes(amount_tbd: true, amount: 0)
    end

    it "pays the difference when their shares fall short" do
      contract = contract_with(scope: "run", amount: 2000)
      shows = add_shows(contract)
      payment = run_payment(contract)

      ContractPaymentSyncService.new(shows.last).call

      payment.reload
      expect([ payment.amount.to_f, payment.amount_tbd ]).to eq([ 450.0, false ])
      expect(payment.notes).to eq("Their shares came to $1,550.00, $450.00 under the $2,000.00 minimum.")
    end

    it "closes with nothing owed when their shares reach the minimum" do
      contract = contract_with(scope: "run")
      shows = add_shows(contract)
      payment = run_payment(contract)

      ContractPaymentSyncService.new(shows.last).call

      expect(payment.reload.status).to eq("cancelled")
      expect(payment.notes).to include("so nothing is owed")
    end

    it "never rewrites a paid top-up" do
      contract = contract_with(scope: "run", amount: 2000)
      shows = add_shows(contract)
      payment = run_payment(contract)
      payment.update!(amount: 999, amount_tbd: false, status: "paid")

      ContractPaymentSyncService.new(shows.last).call

      expect(payment.reload.amount.to_f).to eq(999.0)
    end

    it "says so in the deal" do
      lines = contract_with(scope: "run").deal_summary
      expect(lines).to include({ label: "Minimum guarantee", value: "They take home at least $500.00 for the whole run" })
    end
  end

  it "reads an older guarantee with no scope as per show, under either saved key" do
    contract = contract_with(scope: nil)
    contract.update!(draft_data: contract.draft_data.deep_merge("payment_config" => { "revenue_has_guarantee" => nil, "revenue_guarantee" => "true" }))

    expect(contract.guarantee_per_show?).to be true
    expect(contract.guarantee_for_run?).to be false
  end
end
