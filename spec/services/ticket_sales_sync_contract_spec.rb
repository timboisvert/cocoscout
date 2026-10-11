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

  after { Current.reset }

  it "moves the contractor's share with each sale" do
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_share")

    # 2 × $20 of ticket revenue, 20% to them.
    expect(show.show_financials.reload.ticket_revenue).to eq(40.to_d)
    expect(payment.reload.attributes.values_at("amount", "amount_tbd")).to eq([ 8.to_d, false ])
  end

  # Tim, 2026-10-10: sales typed on the show's page (Sold elsewhere) only
  # reached the contract when someone saved the worksheet.
  it "moves the share when tickets sold elsewhere are typed on the show's page" do
    hot_tix = organization.ticket_sources.create!(name: "Hot Tix")
    TicketOutsideSales.record!(listing, { hot_tix.id.to_s => { general.id.to_s => { "tickets" => "5", "amount" => "$100" } } })

    expect(show.show_financials.reload.ticket_revenue).to eq(100.to_d)
    expect(payment.reload.attributes.values_at("amount", "amount_tbd")).to eq([ 20.to_d, false ])
  end

  # Tim, 2026-10-11: that running share sat in Money → Payouts' To pay for a
  # show still to come. It isn't owed until the show is over.
  it "keeps a future show's share out of To pay until the show is over" do
    contract.update!(contractor: create(:contractor, organization: organization, person: create(:person), name: "It Left The Group Chat"))
    payment.update!(direction: "outgoing") # we sell, so we pay them their share
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_future")
    expect(payment.reload.amount).to eq(8.to_d)
    expect(payment).to be_settles_after_show

    manager = create(:user).tap { |u| create(:organization_role, :manager, user: u, organization: organization) }
    Current.organization = organization
    to_pay = lambda do |org|
      MoneyTodoService.new(user: manager, organization: org).payouts.items
                      .select { |i| i[:kind] == :contract }.sum { |i| i[:amounts][:to_pay].to_f }
    end
    expect(to_pay.call(organization)).to eq(0)

    travel_to show.date_and_time + 1.day do
      expect(payment.reload).not_to be_settles_after_show
      expect(to_pay.call(organization)).to eq(8.0)
    end
  end
end
