# frozen_string_literal: true

require "rails_helper"

# Tickets sold on other sites (Tim, 2026-10-06): the counts a theater types
# on a show's page live in Show Financials, and when the show says so they
# take seats from the room, so CocoScout never oversells a show listed in
# two places. They count against the room, never a ticket type.
RSpec.describe Ticketing::Inventory, "with tickets sold elsewhere" do
  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50) }
  let(:ticket_tailor) { org.ticket_sources.create!(name: "Ticket Tailor") }

  def sold_elsewhere(count, source: ticket_tailor)
    financials = listing.show.show_financials || listing.show.create_show_financials!
    financials.ticket_sales_lines.find_or_initialize_by(ticket_source: source).update!(tickets_sold: count, amount: 0)
  end

  it "takes those seats out of the room, and the CocoScout row never counts" do
    sold_elsewhere(10)
    TicketSalesSync.source_for(org).then { |mine| (listing.show.show_financials.ticket_sales_lines.create!(ticket_source: mine, tickets_sold: 99, amount: 0)) }

    inventory = listing.inventory
    expect([ inventory.outside_sold, inventory.remaining, inventory.remaining(tier: general) ]).to eq([ 10, 40, 40 ])
    expect(inventory.fits?({ general => 40 })).to be(true)
    expect(inventory.fits?({ general => 41 })).to be(false)

    sold_elsewhere(50)
    expect(listing.inventory.sold_out?).to be(true)
  end

  it "shrinks the room but not a type's own seats, and can be switched off" do
    vip = listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500, quantity: 10)
    sold_elsewhere(15)

    inventory = listing.inventory
    expect([ inventory.remaining, inventory.remaining(tier: general), inventory.remaining(tier: vip) ]).to eq([ 45, 45, 10 ])

    listing.update!(outside_sales_reduce_seats: false)
    inventory = listing.inventory
    expect([ inventory.outside_sold, inventory.remaining ]).to eq([ 15, 60 ])
  end

  it "has nothing to reduce when the seats are unlimited" do
    general.update!(quantity: nil)
    sold_elsewhere(15)
    expect(listing.inventory.remaining).to be_nil
  end
end
