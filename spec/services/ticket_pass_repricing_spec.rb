# frozen_string_literal: true

require "rails_helper"

# Returning part of a pass (Tim, 2026-10-05): "people could buy a pass, get
# the discount, then cancel one". So the shows they keep go back to their
# regular price; the saving stays with the kept show, and refunding that one
# later gives its regular price back, so the whole pass always refunds in
# full. A canceled show refunds its full share, and so can a manager.
RSpec.describe TicketPassRepricing do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:part_one) { create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 2.weeks.from_now)) }
  let(:part_two) { create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 2.weeks.from_now + 1.day)) }
  let!(:one_general) { part_one.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10) }
  let!(:two_general) { part_two.ticket_tiers.create!(name: "General", price_cents: 4_000, quantity: 10) }

  before { allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_pass")) }

  def bought(price_cents)
    pass = org.ticket_passes.create!(name: "Double Feature", price_cents: price_cents, status: "on_sale",
                                     pass_shows_attributes: [ { ticket_tier_id: one_general.id }, { ticket_tier_id: two_general.id } ])
    order = TicketCheckout.start_pass!(pass: pass, quantity: 1)
    TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_pass")
    order.ticket_purchase.ticket_orders.reload.to_a
  end

  def tickets_back(refund)
    refund.amount_cents - refund.fees_cents
  end

  it "prices the show they keep at regular, then refunds that show's regular price, the pass in full" do
    first, second = bought(4_500) # shares $15 and $30; savings $5 and $10

    refund = TicketOrderRefund.issue!(first)
    expect(tickets_back(refund)).to eq(500)
    expect(refund.repriced_cents).to eq(1_000)
    expect(second.tickets.first.reload.discount_cents).to eq(0)
    expect(part_two.show.reload.show_financials.ticket_sales_lines.pluck(:amount)).to eq([ 40.to_d ])
    expect(part_one.show.reload.show_financials&.ticket_sales_lines.to_a).to be_empty

    later = TicketOrderRefund.issue!(second.reload)
    expect(tickets_back(later)).to eq(4_000)
    expect(tickets_back(refund) + tickets_back(later)).to eq(4_500)
    # The cash ledger, the books and the tax report all still agree.
    expect(BooksReconciliation.check(org)).to eq([])
  end

  it "refunds the full share when the manager chooses, or the show is canceled" do
    first, second = bought(4_500)

    expect(TicketOrderRefund.quote(first, reprice: false).repriced_cents).to eq(0)
    refund = TicketOrderRefund.issue!(first, reprice: false)
    expect(tickets_back(refund)).to eq(1_500)
    expect(second.tickets.first.reload.discount_cents).to eq(1_000)
  end

  it "never asks the buyer for money: a cheap show returned only takes back what it would have refunded" do
    first, second = bought(3_000) # shares $10 and $20; savings $10 and $20

    refund = TicketOrderRefund.issue!(first)
    expect(tickets_back(refund)).to eq(0)
    expect(refund.repriced_cents).to eq(1_000)
    expect(second.tickets.first.reload.discount_cents).to eq(1_000)
  end

  it "leaves ordinary tickets alone" do
    order = TicketCheckout.start!(listing: part_one, quantities: { one_general.id.to_s => "2" })
    TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_plain")

    expect(TicketOrderRefund.quote(order.reload).repriced).to eq([])
  end
end
