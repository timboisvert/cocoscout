# frozen_string_literal: true

require "rails_helper"

# Every number about a show's tickets, from one place.
RSpec.describe Ticketing::ListingStats do
  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50) }
  let!(:vip) { listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500, quantity: 10) }
  let(:door) { TicketDoor.new(listing, create(:user)) }

  before { allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1")) }

  def buy(quantities, channel: "online", code: nil, at: Time.current)
    travel_to(at) do
      order = TicketCheckout.start!(listing: listing, quantities: quantities.transform_keys { |t| t.id.to_s }, code: code, channel: channel)
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{SecureRandom.hex(4)}")
      order.reload
    end
  end

  it "counts sold, comps, money, refunds, check-ins, channels, codes and the daily series" do
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    TicketDiscountCode.create!(organization: org, ticket_listing: listing, code: "FRIENDS", kind: "fixed", amount_cents: 500, active: true)

    first = buy({ general => 2 }, at: 3.days.ago)          # $40 face
    buy({ vip => 1 }, channel: "embed", at: 1.day.ago)     # $35 face
    buy({ general => 1 }, code: "FRIENDS")                 # $15 face after $5 off
    door.sell({ general.id.to_s => "1" }, kind: "cash")    # $20 face, in the box
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Guest", email: nil, tier: general, quantity: 2) ], by: nil)
    TicketOrderRefund.issue!(first, ticket_ids: [ first.tickets.first.id ])
    door.check_in(first.tickets.last.code)

    stats = described_class.of(listing)
    # 2 + 1 + 1 + 1 at the door + 2 comps, less the one refunded.
    expect([ stats.sold, stats.comps, stats.paid_sold, stats.checked_in, stats.refunded_tickets ]).to eq([ 6, 2, 4, 2, 1 ])
    expect(stats.gross_cents).to eq(2_000 + 3_500 + 1_500 + 2_000)
    expect(stats.tax_cents).to eq(205 + 359 + 154 + 205)
    expect(stats.capacity).to eq(60)
    expect(stats.by_tier.map { |r| [ r.tier.name, r.sold, r.remaining, r.gross_cents ] })
      .to eq([ [ "General", 5, 45, 5_500 ], [ "VIP", 1, 9, 3_500 ] ])
    expect(stats.discount_uses).to eq([ [ "FRIENDS", 1, 500 ] ])
    expect(stats.sold_since(2.days.ago)).to eq(5)

    # What the theater keeps: each order's net, less the refund it gave up,
    # without the tax it collected for the government.
    expected_net = listing.ticket_orders.where(money_path: "cocoscout").sum(:org_net_cents) + 2_205 -
                   TicketRefund.sum(:org_debit_cents) - stats.tax_cents
    expect(stats.net_cents).to eq(expected_net)
    expect(stats.no_shows).to be_nil

    listing.show.update!(date_and_time: 1.hour.ago)
    expect(described_class.of(listing).no_shows).to eq(4)
  end

  it "reads at a glance: sold anywhere, of the seats left once comps are set aside (Tim, 2026-10-09)" do
    buy({ general => 2 })
    door.sell({ general.id.to_s => "3" }, kind: "comp")
    tailor = org.ticket_sources.create!(name: "Ticket Tailor")
    TicketOutsideSales.record!(listing, { tailor.id.to_s => { general.id.to_s => { "tickets" => "5" } } })

    stats = described_class.of(TicketListing.find(listing.id))
    expect([ stats.sold_anywhere, stats.seats_to_sell, stats.comps, stats.capacity ]).to eq([ 7, 57, 3, 60 ])
    # Seats left either way: 57 - 7 = 60 - 2 - 3 - 5.
    expect(stats.seats_to_sell - stats.sold_anywhere).to eq(stats.remaining)
    # Each type reads the same way: 7 of 47 General, 40 remaining.
    row = stats.by_tier.find { |r| r.tier == general }
    expect([ row.sold_here, row.outside, row.comps, row.sold_anywhere, row.seats_to_sell, row.remaining ]).to eq([ 2, 5, 3, 7, 47, 40 ])

    html = ApplicationController.render(partial: "shared/ticket_sales_panel", locals: { listing: stats.listing, stats: stats })
    expect(html).to include(%(<span class="font-semibold tabular-nums">7</span> <span class="text-gray-500">of 57</span> sold), "· 3 comps")
  end

  it "builds many shows at once, matching one at a time" do
    other = create(:ticket_listing, organization: org)
    other_tier = other.ticket_tiers.create!(name: "General", price_cents: 1_000)
    buy({ general => 3 })
    order = TicketCheckout.start!(listing: other, quantities: { other_tier.id.to_s => "2" })
    TicketOrderSettlement.settle!(order)

    batch = described_class.for([ listing, other ])
    expect(batch.transform_values(&:sold)).to eq(listing.id => 3, other.id => 2)
    expect(batch[listing.id].gross_cents).to eq(described_class.of(listing).gross_cents)
  end

  it "is all zeros for a show with no tickets yet" do
    stats = described_class.of(listing)
    expect([ stats.sold, stats.gross_cents, stats.net_cents ]).to eq([ 0, 0, 0 ])
  end
end
