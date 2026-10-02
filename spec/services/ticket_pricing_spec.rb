# frozen_string_literal: true

require "rails_helper"

# 50¢ per paid ticket to us; card processing (2.9% + 30¢) at cost, once per
# order; one switch for who covers both. The theater's numbers must come out
# to the cent every time.
RSpec.describe TicketPricing do
  def tickets(price, count, discount: 0, tax: 0)
    Array.new(count) { { price_cents: price, discount_cents: discount, tax_cents: tax } }
  end

  context "when the buyer pays the fees" do
    it "grosses a $20 ticket up to $21.42 so the theater nets $20" do
      quote = described_class.quote(items: tickets(2_000, 1), fee_mode: "buyer")
      expect(quote.to_h.slice(:total_cents, :buyer_fee_cents, :platform_fee_cents, :processing_cents, :org_net_cents))
        .to eq(total_cents: 2_142, buyer_fee_cents: 142, platform_fee_cents: 50, processing_cents: 92, org_net_cents: 2_000)
    end

    it "charges processing's 30¢ once per order, so a pair costs less per ticket" do
      quote = described_class.quote(items: tickets(2_000, 2), fee_mode: "buyer")
      expect([ quote.total_cents, quote.org_net_cents ]).to eq([ 4_253, 4_000 ])
      expect(quote.buyer_fee_cents / 2.0).to be < 142
    end

    it "always leaves the theater exactly its ticket money, whatever the price and count" do
      [ 100, 500, 1_500, 2_000, 2_499, 4_999, 10_000, 25_000 ].each do |price|
        (1..10).each do |count|
          quote = described_class.quote(items: tickets(price, count), fee_mode: "buyer")
          expect(quote.org_net_cents).to eq(price * count), "#{count} × #{price}¢"
          expect(quote.processing_cents).to eq(described_class.processing_cents(quote.total_cents))
          expect(quote.total_cents - quote.processing_cents - quote.platform_fee_cents).to eq(price * count)
        end
      end
    end
  end

  context "when the theater absorbs the fees" do
    it "charges the buyer $20 and nets the theater $18.62" do
      quote = described_class.quote(items: tickets(2_000, 1), fee_mode: "org")
      expect([ quote.total_cents, quote.buyer_fee_cents, quote.processing_cents, quote.org_net_cents ])
        .to eq([ 2_000, 0, 88, 1_862 ])
    end

    it "nets $37.54 on a pair" do
      quote = described_class.quote(items: tickets(2_000, 2), fee_mode: "org")
      expect([ quote.total_cents, quote.processing_cents, quote.org_net_cents ]).to eq([ 4_000, 146, 3_754 ])
    end
  end

  it "charges nothing on free tickets, and our 50¢ only on paid ones" do
    free = described_class.quote(items: tickets(0, 3), fee_mode: "buyer")
    expect([ free.total_cents, free.platform_fee_cents, free.processing_cents, free.org_net_cents ]).to eq([ 0, 0, 0, 0 ])

    mixed = described_class.quote(items: tickets(0, 2) + tickets(2_000, 1), fee_mode: "buyer")
    expect([ mixed.paid_ticket_count, mixed.platform_fee_cents, mixed.total_cents ]).to eq([ 1, 50, 2_142 ])
  end

  it "takes discounts off before fees, and a fully discounted ticket is free" do
    quote = described_class.quote(items: tickets(2_000, 1, discount: 500), fee_mode: "org")
    expect([ quote.discount_cents, quote.total_cents ]).to eq([ 500, 1_500 ])

    comped = described_class.quote(items: tickets(2_000, 1, discount: 2_000), fee_mode: "buyer")
    expect([ comped.paid_ticket_count, comped.total_cents ]).to eq([ 0, 0 ])
  end

  it "charges tax on top and hands it to the theater with its money" do
    quote = described_class.quote(items: tickets(2_000, 1, tax: 205), fee_mode: "buyer")
    expect([ quote.tax_cents, quote.org_net_cents ]).to eq([ 205, 2_205 ])
    expect(quote.total_cents - quote.processing_cents - quote.platform_fee_cents).to eq(2_205)
  end

  it "takes no fees on cash at the door or comps" do
    cash = described_class.quote(items: tickets(2_000, 2), fee_mode: "buyer", money_path: "cash")
    expect([ cash.total_cents, cash.platform_fee_cents, cash.processing_cents, cash.org_net_cents ]).to eq([ 4_000, 0, 0, 4_000 ])
  end

  it "prices a tier all-in for the page, following the listing's fee switch" do
    listing = create(:ticket_listing)
    tier = create(:ticket_tier, ticket_listing: listing, price_cents: 2_000)
    expect(described_class.all_in_price_cents(listing, tier)).to eq(2_142)

    listing.update!(fee_mode: "org")
    expect(described_class.all_in_price_cents(listing, tier)).to eq(2_000)
  end
  describe ".all_in_price_cents" do
    let(:org) { create(:organization, :pro) }
    let(:listing) { create(:ticket_listing, organization: org) }
    let(:tier) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

    it "is what one ticket really costs: fees in, and tax added on top in too" do
      expect(described_class.all_in_price_cents(listing, tier)).to eq(2_142)
      TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
      expect(described_class.all_in_price_cents(listing, tier)).to eq(2_353)
      TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "included")
      expect(described_class.all_in_price_cents(listing, tier)).to eq(2_142)
    end

    it "never totals more at checkout than the prices shown added up" do
      TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
      one = described_class.all_in_price_cents(listing, tier)
      (1..10).each do |n|
        items = Array.new(n) { { price_cents: 2_000, discount_cents: 0, tax_cents: 205 } }
        expect(described_class.quote(items: items, fee_mode: "buyer").total_cents).to be <= n * one
      end
    end
  end
end
