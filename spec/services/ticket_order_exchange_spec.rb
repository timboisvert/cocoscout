# frozen_string_literal: true

require "rails_helper"

# Moving tickets to another date: the buyer keeps their payment and gets new
# tickets; the theater's money, the tax and the books follow the tickets to
# the new show; a cheaper date refunds the difference; a pricier one is
# refused.
RSpec.describe TicketOrderExchange do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro) }
  let(:friday) { create(:ticket_listing, organization: org) }
  let(:saturday) { create(:ticket_listing, organization: org, show: create(:show, production: friday.production)) }
  let!(:general) { friday.ticket_tiers.create!(name: "General", price_cents: 2_000) }
  let!(:saturday_general) { saturday.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10) }
  let(:manager) { create(:user) }

  before do
    friday.show.update!(date_and_time: 5.days.from_now.change(hour: 19, min: 30))
    saturday.show.update!(date_and_time: 6.days.from_now.change(hour: 20))
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
  end

  def sold(count, listing: friday, tier: general, intent: "pi_sale")
    order = TicketCheckout.start!(listing: listing, quantities: { tier.id.to_s => count.to_s })
    order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: intent)
    order.reload
  end

  def advance_for(listing)
    account = ChartOfAccounts.account(org, :advance_ticket_sales)
    -JournalLine.where(ledger_account_id: account.id, show_id: listing.show_id).sum(:amount_cents)
  end

  it "moves the whole order: new tickets, the money and the books follow" do
    order = sold(2) # $42.53; the theater keeps $40.00
    old_codes = order.tickets.pluck(:code)

    exchange = nil
    expect { exchange = described_class.exchange!(order, target: saturday, by: manager) }
      .to have_enqueued_mail(TicketOrderMailer, :moved)
    moved = exchange.to_order

    expect([ order.reload.status, order.tickets.pluck(:status).uniq ]).to eq([ "exchanged", [ "exchanged" ] ])
    expect(moved.attributes.slice("status", "ticket_listing_id", "exchanged_from_id", "org_net_cents", "total_cents", "paid_at"))
      .to eq("status" => "paid", "ticket_listing_id" => saturday.id, "exchanged_from_id" => order.id,
             "org_net_cents" => 4_000, "total_cents" => 4_253, "paid_at" => order.paid_at)
    expect(moved.payment_intent_id).to eq("pi_sale")
    expect(moved.tickets.pluck(:status, :ticket_tier_id)).to all(eq([ "valid", saturday_general.id ]))
    expect(moved.tickets.pluck(:code) & old_codes).to be_empty
    expect(exchange.moved_cents).to eq(4_000)

    # Seats, numbers, money and books all say Saturday now.
    expect([ friday.inventory.sold, saturday.inventory.sold ]).to eq([ 0, 2 ])
    stats = Ticketing::ListingStats.for([ friday, saturday ])
    expect([ stats[friday.id].net_cents, stats[saturday.id].net_cents ]).to eq([ 0, 4_000 ])
    expect(OrgCashEntry.balance_cents(org)).to eq(4_000)
    expect(TicketBalance.summary(org).upcoming_cents).to eq(4_000)
    expect([ advance_for(friday), advance_for(saturday) ]).to eq([ 0, 4_000 ])
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    expect(BooksReconciliation.check(org)).to be_empty
    expect(friday.show.reload.show_financials.ticket_sales_lines).to be_empty
    expect(saturday.show.reload.show_financials.ticket_sales_lines.sole.tickets_sold).to eq(2)

    # The payment's own webhook arriving again changes nothing.
    TicketOrderSettlement.settle!(order.reload, payment_intent_id: "pi_sale")
    expect(order.reload.status).to eq("exchanged")

    # Refunding the moved order gives everything back from the one payment.
    refund = TicketOrderRefund.issue!(moved)
    expect(Stripe::Refund).to have_received(:create).with(hash_including(payment_intent: "pi_sale", amount: 4_253), anything)
    expect(refund.org_debit_cents).to eq(4_153)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    expect(advance_for(saturday)).to eq(0)
  end

  it "keeps the money held for the new date when the old one happens first" do
    order = sold(1)
    described_class.exchange!(order, target: saturday, email_them: false)

    travel_to(friday.show.date_and_time + 2.days) do
      TicketMoneyRelease.release!(friday.reload)
      expect(TicketBalance.summary(org).upcoming_cents).to eq(2_000)
      expect(TicketBalance.available_cents(org)).to eq(0)
    end
  end

  it "moves some tickets, splitting the fees so none come back twice" do
    order = sold(2) # $2.53 of fees
    first, second = order.tickets.order(:id).to_a

    exchange = described_class.exchange!(order, target: saturday, ticket_ids: [ first.id ], email_them: false)
    expect([ order.reload.status, exchange.fees_cents, exchange.moved_cents ]).to eq([ "paid", 126, 2_000 ])

    left = TicketOrderRefund.issue!(order, ticket_ids: [ second.id ])
    moved = TicketOrderRefund.issue!(exchange.to_order)
    expect([ left.amount_cents, moved.amount_cents ]).to eq([ 2_127, 2_126 ])
    expect(OrgCashEntry.balance_cents(org)).to eq(4_000 - left.org_debit_cents - moved.org_debit_cents)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
  end

  it "refunds the difference for a cheaper ticket type, and refuses a pricier one" do
    student = saturday.ticket_tiers.create!(name: "Student", price_cents: 1_500)
    vip = saturday.ticket_tiers.create!(name: "VIP", price_cents: 3_000)
    order = sold(2)

    expect { described_class.plan(order, target: saturday, chosen_tiers: { general.id => vip.id }) }
      .to raise_error(described_class::Error, /VIP costs \$30\.00.*more than their \$20\.00 ticket/)

    exchange = described_class.exchange!(order, target: saturday, chosen_tiers: { general.id => student.id.to_s }, by: manager)
    expect(exchange.difference_cents).to eq(1_000)
    expect(Stripe::Refund).to have_received(:create).with(hash_including(payment_intent: "pi_sale", amount: 1_000), anything)
    moved = exchange.to_order
    expect(exchange.ticket_refund.attributes.slice("ticket_order_id", "amount_cents", "org_debit_cents", "ticket_ids"))
      .to eq("ticket_order_id" => moved.id, "amount_cents" => 1_000, "org_debit_cents" => 1_000, "ticket_ids" => [])
    expect(moved.tickets.pluck(:price_cents).uniq).to eq([ 1_500 ])
    expect(Ticketing::ListingStats.of(saturday).net_cents).to eq(3_000)
    expect(advance_for(saturday)).to eq(3_000)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    expect(BooksReconciliation.check(org)).to be_empty
  end

  it "moves the tax with the tickets, onto the new show's report" do
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    order = sold(1)
    exchange = described_class.exchange!(order, target: saturday, email_them: false)

    expect(exchange.to_order.tickets.sole.tax_lines.sum(:tax_cents)).to eq(205)
    expect(TaxLine.where(taxable: order.tickets.sole).sum(:tax_cents)).to eq(0)
    expect(BooksReconciliation.check(org)).to be_empty
    by_event = TicketTaxReport.new(org, from: Date.current, to: 1.month.from_now.to_date, basis: "event")
    expect(by_event.total_net_cents).to eq(205)
  end

  it "won't move what can't move" do
    order = sold(2)
    expect { described_class.plan(order, target: friday) }.to raise_error(described_class::Error, /another date/)
    other = create(:ticket_listing, organization: org)
    other.ticket_tiers.create!(name: "General", price_cents: 2_000)
    expect { described_class.plan(order, target: other) }.to raise_error(described_class::Error, /another date/)

    saturday_general.update!(quantity: 1)
    expect { described_class.exchange!(order, target: saturday) }.to raise_error(described_class::Error, /seats left/)
    expect(order.reload.status).to eq("paid")

    TicketDoor.new(friday, manager).check_in_order(order)
    expect { described_class.plan(order.reload, target: saturday) }.to raise_error(described_class::Error, /Choose the tickets/)
  end

  it "tells the door an old ticket moved" do
    order = sold(1)
    described_class.exchange!(order, target: saturday, email_them: false)
    result = TicketDoor.new(friday, manager).check_in(order.tickets.sole.code)
    expect(result.message).to eq("This ticket moved to another date")
  end
end
