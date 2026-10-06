# frozen_string_literal: true

require "rails_helper"

# A contract settling off a show's ticket sales follows what CocoScout sells
# as it sells: the revenue share moves with every settled order, not only
# when someone saves the financials worksheet (Round 9 §0, 2026-10-06).
RSpec.describe TicketSalesSync, "and contract settlement" do
  let(:organization) { create(:organization, :pro) }
  let(:contract) { create(:contract, :revenue_share_per_event, :active, organization: organization) }
  let(:production) { create(:production, organization: organization, production_type: "third_party").tap { |p| contract.update!(production: p) } }
  let(:show) { create(:show, production: production, date_and_time: 7.days.from_now.change(hour: 19)) }
  let(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }
  let!(:payment) { create(:contract_payment, :revenue_share_tbd, contract: contract, due_date: show.date_and_time.to_date + 1) }

  it "moves the contractor's share with each sale" do
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_share")

    # 2 × $20 of ticket revenue, 20% to them.
    expect(show.show_financials.reload.ticket_revenue).to eq(40.to_d)
    expect(payment.reload.attributes.values_at("amount", "amount_tbd")).to eq([ 8.to_d, false ])
  end
end
