# frozen_string_literal: true

require "rails_helper"

# A theater's ticket sales for a period: totals, by show, by type, by
# channel and by day, counted by sale day or show day, with refunds and
# comps where they belong.
RSpec.describe TicketSalesReport do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  # Times, not dates: a Date#change ignores the hour (memory: Time.zone.local in specs).
  let(:this_month) { Time.zone.local(Date.current.year, Date.current.month, 1, 9) }
  let(:show_day) { this_month + 10.days + 10.hours }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: show_day)) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }
  let!(:vip) { listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500, quantity: 10) }

  before { TicketingProfile.for(org).update!(enabled: true) }

  def buy(quantities, at:, name: "Avery Buyer")
    travel_to(at) do
      order = TicketCheckout.start!(listing: listing, quantities: quantities)
      order.update!(buyer_name: name, buyer_email: "#{name.parameterize}@example.com")
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{order.id}", charge_id: "ch_#{order.id}")
      order
    end
  end

  it "adds up the period's sales, by show, type, channel and day" do
    early = buy({ general.id.to_s => "2" }, at: this_month.change(hour: 12), name: "Dana Scully")
    buy({ vip.id.to_s => "1" }, at: (this_month + 3.days).change(hour: 12), name: "Fox Mulder")
    buy({ general.id.to_s => "1" }, at: (this_month - 5.days).change(hour: 12), name: "Last Month")
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Walter", email: nil, tier: general, quantity: 1) ], by: create(:user))
    door = TicketDoor.new(listing, create(:user))
    travel_to((this_month + 4.days).change(hour: 20)) { door.sell({ general.id.to_s => "1" }, kind: "cash") }
    allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_1"))
    TicketOrderRefund.issue!(early, ticket_ids: [ early.tickets.first.id ])

    report = described_class.new(org, from: this_month.to_date, to: this_month.end_of_month.to_date)
    s = report.summary
    # Sold this month: 2 General (1 refunded) + 1 VIP + 1 cash General = 3 paid tickets left; the comp apart.
    expect([ s.tickets, s.comps, s.orders ]).to eq([ 3, 1, 3 ])
    expect(s.gross_cents).to eq(2_000 + 3_500 + 2_000)
    expect(s.refunded_cents).to eq(TicketRefund.sole.amount_cents)
    expect(s.platform_fee_cents).to eq(150 - 50)

    expect(report.by_show.map { |r| [ r.listing.id, r.tickets, r.comps, r.money_state ] }).to eq([ [ listing.id, 3, 1, "Held for the show" ] ])
    expect(report.by_type.map { |r| [ r.name, r.tickets, r.gross_cents ] }).to eq([ [ "General", 2, 4_000 ], [ "VIP", 1, 3_500 ] ])
    expect(report.by_channel.map { |r| [ r.channel, r.tickets ] }).to contain_exactly([ "online", 2 ], [ "door_cash", 1 ], [ "comp", 1 ])
    expect(report.by_day.values.sum).to eq(3)
    expect(report.by_day[this_month.to_date.iso8601]).to eq(1)

    # By show day instead: everything for the show lands in its month, last month's sale included.
    by_event = described_class.new(org, from: this_month.to_date, to: this_month.end_of_month.to_date, basis: "event")
    expect(by_event.summary.tickets).to eq(4)
    expect(by_event.by_day[show_day.to_date.iso8601]).to eq(4)

    csv = report.to_csv
    expect(csv).to include("Rising Stars", "Total,,3,1,75.00")
    buyers = report.buyers_csv
    expect(buyers).to include("Dana Scully", "dana-scully@example.com", "Fox Mulder", "Walter")
    expect(buyers).not_to include("Last Month")
  end
end
