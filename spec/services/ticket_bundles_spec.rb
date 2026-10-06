# frozen_string_literal: true

require "rails_helper"

# A bundle (Tim, 2026-10-05): "4 × General for $70". It admits several people
# of another ticket type, using that type's seats. Each purchase becomes one
# General ticket per person, splitting the price and remembering the bundle,
# with our 50¢ for each person. Plain ticket types never ask about any of it.
RSpec.describe "Ticket bundles" do
  include ActionView::Helpers::NumberHelper
  include TicketingHelper

  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: 2.weeks.from_now)) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10, position: 0) }
  let!(:pack) { listing.ticket_tiers.create!(name: "4-pack", price_cents: 7_000, admits: 4, bundle_of: general, position: 1) }

  it "sells a bundle as four General tickets of $17.50 that use General's seats, with 50¢ for each person" do
    order = TicketCheckout.start!(listing: listing, quantities: { pack.id.to_s => "1" })

    expect(order.tickets.pluck(:ticket_tier_id, :bundle_tier_id, :price_cents)).to eq([ [ general.id, pack.id, 1_750 ] ] * 4)
    expect(order.platform_fee_cents).to eq(200)
    expect(order.total_cents).to eq(TicketPricing.all_in_price_cents(listing, pack))
    expect(listing.inventory.remaining(tier: general)).to eq(6)
    expect(pack.units_for(listing.inventory.remaining(tier: pack))).to eq(1)
    expect(TicketCheckout.held_quantities(order)).to eq(pack.id => 1)
    # Only the bundle's own name: what it admits is the theater's to say in its description.
    expect(ticket_summary_lines(order).first.first(2)).to eq([ "1 × 4-pack", 7_000 ])
  end

  it "shares General's seats with single tickets, and counts people against the order limit" do
    TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "7" })
    expect { TicketCheckout.start!(listing: listing, quantities: { pack.id.to_s => "1" }) }
      .to raise_error(TicketCheckout::Error, /aren't enough seats/)

    listing.update!(max_per_order: 6)
    expect { TicketCheckout.start!(listing: listing, quantities: { pack.id.to_s => "1", general.id.to_s => "3" }) }
      .to raise_error(TicketCheckout::Error, "You can buy up to 6 tickets at a time.")
  end

  it "keeps a plain ticket type at one person with no bundle questions, and a bundle without seats of its own" do
    general.update!(admits: 5)
    expect(general.reload.admits).to eq(1)
    pack.update!(quantity: 30)
    expect(pack.reload.quantity).to be_nil
    expect(listing.inventory.capacity).to eq(10)
    expect(listing.ticket_tiers.build(name: "Bad", price_cents: 100, admits: 1, bundle_of: general)).not_to be_valid
  end

  it "splits a price that doesn't divide evenly so the tickets still add up" do
    expect(TicketTier.split(7_001, 4)).to eq([ 1_751, 1_750, 1_750, 1_750 ])
  end

  it "gives a bundle as four General tickets, and sells one at the door the same way" do
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Guest Gail", email: nil, tier: pack, quantity: 1) ], by: create(:user), email_them: false)
    expect(Ticket.where(ticket_tier: general, bundle_tier: pack).count).to eq(4)

    order = TicketDoor.new(listing, create(:user)).sell({ pack.id.to_s => "1" }, kind: "cash", buyer_name: "Walk Up")
    expect(order.tickets.pluck(:ticket_tier_id).uniq).to eq([ general.id ])
    expect(order.tickets.pluck(:status).uniq).to eq([ "checked_in" ])
    expect(listing.inventory.remaining(tier: general)).to eq(2)
  end

  it "follows a production's bundle onto each date, pointing at that date's own General" do
    production = create(:production, organization: org)
    setup = ProductionTicketing.create!(production: production, organization: org)
    base = setup.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50, position: 0)
    setup.ticket_tiers.create!(name: "4-pack", price_cents: 7_000, admits: 4, bundle_of: base, position: 1)
    date = create(:ticket_listing, organization: org, production: production, inherits_tiers: true,
                                   show: create(:show, production: production, date_and_time: 3.weeks.from_now))
    ProductionTicketingSync.sync!(date, setup)

    copy = date.ticket_tiers.find_by(name: "4-pack")
    expect([ copy.admits, copy.bundle_of, copy.quantity ]).to eq([ 4, date.ticket_tiers.find_by(name: "General"), nil ])
  end
end
