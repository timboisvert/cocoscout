# frozen_string_literal: true

require "rails_helper"

# A ticket type that admits several people for one price (Tim, 2026-10-05):
# "4 tickets for $70". Each purchase becomes one ticket per person, splitting
# the price, taking that many seats, and carrying our 50¢ for each person.
RSpec.describe "Ticket bundles" do
  include ActionView::Helpers::NumberHelper
  include TicketingHelper

  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: 2.weeks.from_now)) }
  let!(:single) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 40, position: 0) }
  let!(:pack) { listing.ticket_tiers.create!(name: "4-pack", price_cents: 7_000, admits: 4, quantity: 8, position: 1) }

  it "sells a 4-pack as four tickets of $17.50 that take four seats, with 50¢ for each person" do
    order = TicketCheckout.start!(listing: listing, quantities: { pack.id.to_s => "1" })

    expect(order.tickets.pluck(:price_cents)).to eq([ 1_750, 1_750, 1_750, 1_750 ])
    expect(order.platform_fee_cents).to eq(200)
    expect(order.total_cents).to eq(TicketPricing.all_in_price_cents(listing, pack))
    expect(listing.inventory.remaining(tier: pack)).to eq(4)
    expect(TicketCheckout.held_quantities(order)).to eq(pack.id => 1)
    expect(ticket_summary_lines(order).first.first(2)).to eq([ "1 × 4-pack (admits 4)", 7_000 ])
  end

  it "counts the people against the seats and the order limit" do
    listing.update!(max_per_order: 6)
    expect { TicketCheckout.start!(listing: listing, quantities: { pack.id.to_s => "2" }) }
      .to raise_error(TicketCheckout::Error, "You can buy up to 6 tickets at a time.")

    listing.update!(max_per_order: 10)
    TicketCheckout.start!(listing: listing, quantities: { pack.id.to_s => "2" })
    expect { TicketCheckout.start!(listing: listing, quantities: { pack.id.to_s => "1" }) }
      .to raise_error(TicketCheckout::Error, /aren't enough seats/)
  end

  it "splits a price that doesn't divide evenly so the tickets still add up" do
    expect(TicketTier.split(7_001, 4)).to eq([ 1_751, 1_750, 1_750, 1_750 ])
  end

  it "gives a pack as four tickets, and sells one at the door the same way" do
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Guest Gail", email: nil, tier: pack, quantity: 1) ], by: create(:user), email_them: false)
    expect(Ticket.where(ticket_tier: pack).count).to eq(4)

    order = TicketDoor.new(listing, create(:user)).sell({ pack.id.to_s => "1" }, kind: "cash", buyer_name: "Walk Up")
    expect(order.tickets.count).to eq(4)
    expect(order.tickets.pluck(:status).uniq).to eq([ "checked_in" ])
    expect(listing.inventory.remaining(tier: pack)).to eq(0)
  end
end
