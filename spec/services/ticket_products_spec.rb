# frozen_string_literal: true

require "rails_helper"

# Products bought with tickets (a bottle for the table): on the hold, priced
# without our 50¢, settled into their own books accounts, into the show's
# financials as the theater chose, refunded with the tickets, handed over at
# the door, and along for the ride when every ticket moves to another date.
RSpec.describe "Ticket products", type: :service do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:show) { create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 19, min: 30)) }
  let(:bottle) { create(:ticket_product, organization: org, name: "Champagne bottle", price_cents: 4_500) }
  let(:program) { create(:ticket_product, organization: org, name: "Program", price_cents: 500, counts_toward_ticket_revenue: true) }
  # The production's setup comes first: a listing reads it when it's made.
  let!(:setup) do
    TicketingProfile.for(org).update!(enabled: true)
    ProductionTicketing.for(production).tap do |setup|
      setup.production_ticketing_products.create!(ticket_product: bottle, position: 0)
      setup.production_ticketing_products.create!(ticket_product: program, position: 1)
    end
  end
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  def balance(key)
    ChartOfAccounts.account(org, key).natural_balance_cents
  end

  def checkout_with_bottle(count = 2)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    TicketCheckout.set_items!(order, { bottle.id.to_s => "1", program.id.to_s => "2" })
    order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
    order.reload
  end

  it "adds products to a hold without our 50¢, keeps the total at or below the prices shown, and settles them" do
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    before = order.total_cents
    bottle_all_in = TicketPricing.all_in_product_price_cents(listing, listing.product_offers.first)

    TicketCheckout.set_items!(order, { bottle.id.to_s => "1", "999" => "3" })
    order.reload
    expect(order.ticket_order_items.map { |i| [ i.name, i.quantity, i.unit_price_cents, i.status ] }).to eq([ [ "Champagne bottle", 1, 4_500, "reserved" ] ])
    expect(order.platform_fee_cents).to eq(100)
    expect(order.subtotal_cents).to eq(4_000 + 4_500)
    expect(order.total_cents - before).to be <= bottle_all_in
    expect(order.org_net_cents).to eq(8_500)

    # Taking it off again.
    TicketCheckout.set_items!(order, { bottle.id.to_s => "0" })
    expect(order.reload.ticket_order_items).to be_empty
    expect(order.total_cents).to eq(before)

    order = checkout_with_bottle
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
    order.reload
    expect(order.ticket_order_items.pluck(:status).uniq).to eq([ "valid" ])
    expect(balance(:cocoscout_balance)).to eq(4_000 + 4_500 + 1_000)
    expect(balance(:advance_ticket_sales)).to eq(4_000)
    expect(balance(:advance_product_sales)).to eq(5_500)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)

    # Show Financials: the program counts as ticket revenue, the bottle is other revenue.
    financials = show.reload.show_financials
    line = financials.ticket_sales_lines.sole
    expect([ line.tickets_sold, line.amount.to_f ]).to eq([ 2, 40.0 + 10.0 ])
    expect(financials.normalized_other_revenue_details).to eq([ { "description" => "CocoScout products", "amount" => 45.0 } ])

    # The day after the show, both become income.
    travel_to(show.date_and_time + 1.day + 2.hours) { TicketMoneyRelease.release!(listing) }
    expect(balance(:advance_product_sales)).to eq(0)
    expect(balance(:product_income)).to eq(5_500)
    expect(balance(:ticket_income)).to eq(4_000)

    stats = Ticketing::ListingStats.of(listing)
    expect([ stats.products_sold, stats.product_cents, stats.gross_cents ]).to eq([ 3, 5_500, 4_000 ])
    expect(stats.by_product.map { |r| [ r.name, r.sold, r.gross_cents ] }).to contain_exactly([ "Champagne bottle", 1, 4_500 ], [ "Program", 2, 1_000 ])
  end

  it "carries the products over when a buyer changes their tickets, and refuses changes once paid" do
    order = checkout_with_bottle
    replaced = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "3" }, replacing: order.token)
    expect(replaced.id).not_to eq(order.id)
    expect(replaced.ticket_order_items.map { |i| [ i.name, i.quantity ] }).to contain_exactly([ "Champagne bottle", 1 ], [ "Program", 2 ])

    TicketOrderSettlement.settle!(replaced, payment_intent_id: "pi_2", charge_id: "ch_2")
    expect { TicketCheckout.set_items!(replaced.reload, { bottle.id.to_s => "2" }) }.to raise_error(TicketCheckout::Error)
  end

  it "refunds the products with the tickets, or on their own" do
    order = checkout_with_bottle
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
    allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_1"))

    # Only the bottle: its price, no fees, nothing happens to the tickets.
    bottle_item = order.ticket_order_items.find_by!(name: "Champagne bottle")
    refund = TicketOrderRefund.issue!(order.reload, ticket_ids: [ "" ], item_ids: [ bottle_item.id ])
    expect([ refund.amount_cents, refund.product_cents, refund.face_cents, refund.ticket_ids, refund.item_ids ]).to eq([ 4_500, 4_500, 0, [], [ bottle_item.id ] ])
    expect(bottle_item.reload.status).to eq("refunded")
    expect(order.reload.status).to eq("partially_refunded")
    expect(order.tickets.pluck(:status).uniq).to eq([ "valid" ])
    expect(balance(:advance_product_sales)).to eq(1_000)
    expect(show.reload.show_financials.normalized_other_revenue_details).to be_empty

    # The rest of the order: tickets and the programs, fees back too.
    whole = TicketOrderRefund.issue!(order.reload)
    expect(whole.item_ids).to eq([ order.ticket_order_items.find_by!(name: "Program").id ])
    expect(whole.amount_cents).to eq(order.total_cents - 4_500)
    expect(order.reload.status).to eq("refunded")
    expect(balance(:advance_product_sales)).to eq(0)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
  end

  it "sells products for cash at the door only when the production says so, never on a comp, and hands them over" do
    door = TicketDoor.new(listing, create(:user))
    # Off by default: a pre-sold bottle isn't a door item.
    expect(listing.product_offers(at_door: true)).to be_empty
    online_only = door.sell({ general.id.to_s => "1" }, kind: "cash", products: { bottle.id.to_s => "1" })
    expect(online_only.ticket_order_items).to be_empty

    setup.update!(products_at_door: true)
    order = door.sell({ general.id.to_s => "1" }, kind: "cash", products: { bottle.id.to_s => "1" })
    item = order.ticket_order_items.sole
    expect([ item.name, item.status, order.total_cents, order.money_path ]).to eq([ "Champagne bottle", "valid", 6_500, "cash" ])
    # The cash box holds the $20 online-only sale and this $65 one.
    expect(balance(:door_cash)).to eq(2_000 + 6_500)
    expect(balance(:product_income)).to eq(4_500)

    comp = door.sell({ general.id.to_s => "1" }, kind: "comp", products: { bottle.id.to_s => "1" })
    expect(comp.ticket_order_items).to be_empty

    item.update!(fulfilled_quantity: item.quantity, fulfilled_at: Time.current)
    expect(item.fulfilled?).to be(true)
  end

  it "lets a date switch the production's products off for itself" do
    listing.update!(sell_products: false)
    expect(listing.product_offers).to be_empty
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "1" })
    TicketCheckout.set_items!(order, { bottle.id.to_s => "1" })
    expect(order.reload.ticket_order_items).to be_empty
  end

  it "moves the products along when every ticket moves to another date" do
    other_show = create(:show, production: production, date_and_time: 17.days.from_now.change(hour: 19, min: 30))
    target = create(:ticket_listing, organization: org, show: other_show)
    target.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
    order = checkout_with_bottle(1)
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")

    exchange = TicketOrderExchange.exchange!(order.reload, target: target, email_them: false)
    new_order = exchange.to_order
    expect(new_order.ticket_order_items.map { |i| [ i.name, i.quantity, i.status ] }).to contain_exactly([ "Champagne bottle", 1, "valid" ], [ "Program", 2, "valid" ])
    expect(order.reload.ticket_order_items.pluck(:status).uniq).to eq([ "exchanged" ])
    waiting = JournalLine.where(ledger_account: ChartOfAccounts.account(org, :advance_product_sales)).group(:show_id).sum(:amount_cents)
    expect(waiting.reject { |_, v| v.zero? }).to eq({ other_show.id => -5_500 })
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
  end
end
