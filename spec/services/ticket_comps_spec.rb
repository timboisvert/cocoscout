# frozen_string_literal: true

require "rails_helper"

# Giving tickets away: real orders at $0 that take seats and email the
# guests their tickets, all or nothing.
RSpec.describe TicketComps do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 5) }
  let!(:vip) { listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500) }
  let(:manager) { create(:user) }

  it "reads a pasted guest list" do
    guests = described_class.parse(<<~LIST, listing: listing, default_tier: general)
      Dana Scully, Dana@Example.com, 2
      Fox Mulder\tfox@example.com
      Walter Skinner, 3, VIP

    LIST
    expect(guests.map { |g| [ g.name, g.email, g.tier.name, g.quantity ] }).to eq([
      [ "Dana Scully", "dana@example.com", "General", 2 ],
      [ "Fox Mulder", "fox@example.com", "General", 1 ],
      [ "Walter Skinner", nil, "VIP", 3 ]
    ])
  end

  it "gives free tickets that take seats and arrive by email" do
    guests = described_class.parse("Dana Scully, dana@example.com, 2\nWalter Skinner", listing: listing, default_tier: general)

    orders = nil
    expect { orders = described_class.give!(listing, guests, by: manager, note: "Guest of the cast") }
      .to have_enqueued_job(TicketOrderConfirmationJob).exactly(:once)

    dana = orders.first
    expect(dana.attributes.slice("status", "channel", "money_path", "total_cents", "platform_fee_cents", "issued_by_id", "note"))
      .to eq("status" => "paid", "channel" => "comp", "money_path" => "none", "total_cents" => 0,
             "platform_fee_cents" => 0, "issued_by_id" => manager.id, "note" => "Guest of the cast")
    expect(dana.tickets.pluck(:status, :price_cents, :discount_cents)).to all(eq([ "valid", 2_000, 2_000 ]))
    expect(listing.inventory.remaining(tier: general)).to eq(2)
    expect(OrgCashEntry.count + JournalEntry.count).to eq(0)
  end

  it "gives all of them or none" do
    guests = described_class.parse("A, 3\nB, 3", listing: listing, default_tier: general)
    expect { described_class.give!(listing, guests, by: manager) }.to raise_error(described_class::Error, /more than the seats left/)
    expect(TicketOrder.count).to eq(0)
  end

  it "refuses rows it can't use, and a canceled show" do
    bad = described_class.parse("Dana, dana@@example", listing: listing, default_tier: general)
    expect { described_class.give!(listing, bad, by: manager) }.to raise_error(described_class::Error, /Check Dana/)
    expect { described_class.give!(listing, [], by: manager) }.to raise_error(described_class::Error, /at least one/)

    listing.update!(status: "canceled")
    ok = described_class.parse("Dana", listing: listing, default_tier: general)
    expect { described_class.give!(listing, ok, by: manager) }.to raise_error(described_class::Error, /canceled/)
  end
end
