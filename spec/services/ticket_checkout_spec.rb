# frozen_string_literal: true

require "rails_helper"

# Starting an order: seats held for ten minutes, every cent priced — discount,
# tax, our fee, processing — and never more tickets than the room holds.
RSpec.describe TicketCheckout do
  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 3) }

  def start(quantities, **options)
    described_class.start!(listing: listing, quantities: quantities.transform_keys { |tier| tier.id.to_s }, **options)
  end

  it "holds the seats and prices the order all-in" do
    order = start({ general => 2 })

    expect([ order.status, order.tickets.pluck(:status).uniq ]).to eq([ "pending", [ "reserved" ] ])
    expect(order.expires_at).to be_within(5.seconds).of(TicketOrder::HOLD.from_now)
    expect([ order.subtotal_cents, order.total_cents, order.org_net_cents ]).to eq([ 4_000, 4_253, 4_000 ])
    expect(listing.inventory.remaining(tier: general)).to eq(1)
  end

  # Tim (2026-10-02): going back from checkout mustn't lose the tickets or
  # hold a second set.
  describe "coming back to a live hold" do
    let!(:vip) { listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500, quantity: 2) }

    it "reopens the same order and clock for the same tickets" do
      held = start({ general => 2 })
      again = start({ general => "2" }, replacing: held.token)
      expect(again).to eq(held)
      expect(TicketOrder.count).to eq(1)
      expect(listing.inventory.remaining(tier: general)).to eq(1)
    end

    it "swaps the hold when the tickets change, freeing the old seats" do
      held = start({ general => 2 })
      swapped = start({ general => 3 }, replacing: held.token)
      expect(swapped).not_to eq(held)
      expect(held.reload.status).to eq("expired")
      expect(listing.inventory.remaining(tier: general)).to eq(0)
    end

    it "keeps the old hold when the new one doesn't fit" do
      held = start({ general => 2 })
      expect { start({ general => 2, vip => 3 }, replacing: held.token) }.to raise_error(described_class::Error)
      expect(held.reload.status).to eq("pending")
      expect(listing.inventory.remaining(tier: general)).to eq(1)
    end

    it "ignores a token that isn't a live hold for this show" do
      other = start({ general => 1 })
      other.update!(expires_at: 1.minute.ago)
      fresh = start({ general => 1 }, replacing: other.token)
      expect(fresh).not_to eq(other)
      expect(described_class.held_quantities(fresh)).to eq(general.id => 1)
    end
  end

  it "adds the theater's tax and records it per ticket" do
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    order = start({ general => 1 })

    expect(order.tax_cents).to eq(205)
    expect(order.tickets.sole.tax_lines.sole.slice(:name, :rate_bps, :base_cents, :tax_cents, :included))
      .to eq("name" => "Sales tax", "rate_bps" => 1_025, "base_cents" => 2_000, "tax_cents" => 205, "included" => false)
    expect(order.org_net_cents).to eq(2_205)
  end

  it "takes a discount code off before fees and tax" do
    org.ticket_discount_codes.create!(code: "FRIENDS", kind: "fixed", amount_cents: 500, ticket_listing: listing)
    order = start({ general => 1 }, code: "friends")
    expect([ order.discount_cents, order.org_net_cents ]).to eq([ 500, 1_500 ])
  end

  it "shows a hidden tier only to someone with its code" do
    industry = listing.ticket_tiers.create!(name: "Industry", price_cents: 1_000, hidden: true, unlock_code: "INDUSTRY")
    expect { start({ industry => 1 }) }.to raise_error(TicketCheckout::Error, "That ticket isn't on sale.")
    expect(start({ industry => 1 }, code: "industry").tickets.sole.ticket_tier).to eq(industry)
  end

  it "says no plainly: off sale, nothing picked, too many, a bad code, not enough seats" do
    expect { start({}) }.to raise_error(TicketCheckout::Error, "Pick at least one ticket.")
    expect { start({ general => 1 }, code: "NOPE") }.to raise_error(TicketCheckout::Error, "That code doesn't work for this show.")
    expect { start({ general => 4 }) }.to raise_error(TicketCheckout::Error, /aren't enough seats/)
    listing.update!(max_per_order: 2)
    expect { start({ general => 3 }) }.to raise_error(TicketCheckout::Error, "You can buy up to 2 tickets at a time.")
    listing.update!(status: "paused")
    expect { start({ general => 1 }) }.to raise_error(TicketCheckout::Error, /aren't on sale/)
  end

  it "lets the seats go when a hold runs out" do
    start({ general => 3 })
    expect { start({ general => 1 }) }.to raise_error(TicketCheckout::Error, /aren't enough seats/)

    travel 11.minutes do
      expect(start({ general => 1 })).to be_persisted
    end
  end

  # Two buyers after the last seat at the same moment: one gets it. Real
  # threads need committed rows, so this opts out of the wrapping transaction.
  describe "racing for the last seat" do
    uses_transaction "never sells the same seat twice"

    it "never sells the same seat twice", no_transaction: true do
      solo = create(:ticket_listing, organization: org)
      last = solo.ticket_tiers.create!(name: "Last seat", price_cents: 2_000, quantity: 1)

      results = Queue.new
      barrier = Queue.new
      threads = 2.times.map do
        Thread.new do
          barrier.pop
          described_class.start!(listing: solo, quantities: { last.id.to_s => "1" })
          results << :held
        rescue TicketCheckout::Error
          results << :sold_out
        end
      end
      2.times { barrier << true }
      threads.each(&:join)

      expect(2.times.map { results.pop }.sort).to eq(%i[held sold_out])
      expect(solo.tickets.count).to eq(1)
    end
  end
end
