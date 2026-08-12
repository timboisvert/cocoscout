# frozen_string_literal: true

require "rails_helper"

# Contract money summaries used to re-query shows, financials, payments, and
# the sibling-contract count once per contract — so the contracts index and the
# money hub paid a query bundle per row. preload_money_data batches all of it;
# these specs pin that the cost stays flat as contracts are added, and that the
# batched numbers match the per-contract path.
RSpec.describe Contract, "money batching" do
  let(:organization) { create(:organization, :pro) }

  def revenue_share_contract!(name)
    production = create(:production, organization: organization, name: name)
    contract = create(:contract, organization: organization, production: production, status: "active",
                                 draft_data: {
                                   "payment_structure" => "revenue_share",
                                   "payment_config" => {
                                     "revenue_our_share" => 70,
                                     "revenue_their_share" => 30,
                                     "who_sells_tickets" => "org"
                                   }
                                 })
    2.times do |i|
      show = create(:show, production: production, date_and_time: (i + 2).days.ago)
      create(:show_financials, show: show, revenue_type: "ticket_sales",
                               ticket_revenue: 100, data_confirmed: true)
    end
    contract
  end

  it "doesn't cost more per contract" do
    revenue_share_contract!("One")
    contracts = organization.contracts.to_a
    baseline = count_queries do
      Contract.preload_money_data(contracts)
      contracts.each(&:money_display)
    end

    (2..8).each { |i| revenue_share_contract!("Number #{i}") }
    contracts = organization.contracts.reload.to_a
    scaled = count_queries do
      Contract.preload_money_data(contracts)
      contracts.each(&:money_display)
    end

    expect(scaled - baseline).to be <= 2
  end

  it "matches the unbatched per-contract numbers" do
    3.times { |i| revenue_share_contract!("Parity #{i}") }

    batched = Contract.preload_money_data(organization.contracts.to_a).map(&:money_display)
    unbatched = organization.contracts.to_a.map(&:money_display)

    expect(batched).to eq(unbatched)
  end
end
