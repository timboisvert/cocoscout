# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ticketing models" do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs") }
  let(:show) { create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 10, 19, 30)) }

  describe TicketingProfile do
    it "takes its address from the org's name and stays off until a superadmin turns it on" do
      profile = TicketingProfile.for(org)
      expect([ profile.slug, profile.enabled, profile.default_fee_mode ]).to eq([ "stars-garters", false, "buyer" ])
      expect(TicketingProfile.for(org)).to eq(profile)
    end

    it "never takes a word the /t pages use, or someone else's address" do
      profile = TicketingProfile.for(org)
      profile.slug = "orders"
      expect(profile).not_to be_valid

      other = create(:organization, name: "Stars & Garters")
      expect(TicketingProfile.for(other).slug).to eq("stars-garters-2")
    end
  end

  describe TicketListing do
    it "names itself from the production and date, and stops selling online at showtime" do
      listing = TicketListing.create!(show: show)
      expect([ listing.organization, listing.production, listing.slug ]).to eq([ org, production, "improvised-animorphs-oct-10" ])
      expect(listing.off_sale_at).to eq(show.date_and_time)
      expect(listing.status).to eq("draft")
    end

    it "adds the time when a production plays twice in a night" do
      TicketListing.create!(show: show)
      late = create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 10, 21, 30))
      expect(TicketListing.create!(show: late).slug).to eq("improvised-animorphs-oct-10-9pm")
    end

    it "sells only while on sale, inside its window, for a show that's still on" do
      listing = TicketListing.create!(show: show, status: "on_sale", on_sale_at: Time.zone.local(2026, 10, 1, 10))
      expect(listing.selling?(Time.zone.local(2026, 9, 30, 12))).to be(false)
      expect(listing.selling?(Time.zone.local(2026, 10, 5, 12))).to be(true)
      expect(listing.selling?(Time.zone.local(2026, 10, 10, 19, 30))).to be(false)
      show.update!(canceled: true)
      expect(listing.selling?(Time.zone.local(2026, 10, 5, 12))).to be(false)
    end

    it "uses the org's fee switch unless the show overrides it" do
      TicketingProfile.for(org).update!(default_fee_mode: "org")
      listing = TicketListing.create!(show: show)
      expect(listing.effective_fee_mode).to eq("org")
      listing.update!(fee_mode: "buyer")
      expect(listing.effective_fee_mode).to eq("buyer")
    end

    it "refuses a show from another organization" do
      listing = TicketListing.new(show: show, organization: create(:organization))
      expect(listing).not_to be_valid
    end

    it "goes with its show while it's a draft, but not once anyone has bought" do
      listing = TicketListing.create!(show: show)
      show.destroy!
      expect(TicketListing.exists?(listing.id)).to be(false)

      sold_show = create(:show, production: production)
      sold = TicketListing.create!(show: sold_show)
      create(:ticket_order, ticket_listing: sold)
      expect(sold.destroy).to be(false)
      expect(sold.errors.full_messages.join).to include("Cancel it and refund buyers instead")
    end
  end

  describe TicketOrder do
    it "gets a short code people can read out, and a secret link token" do
      order = create(:ticket_order)
      expect(order.code).to match(/\A[A-HJ-NP-Z2-9]{6}\z/)
      expect(order.token.length).to be >= 30
      expect(order.to_param).to eq(order.token)
    end
  end

  describe TicketDiscountCode do
    let(:listing) { TicketListing.create!(show: show) }

    it "takes dollars or percent off, never more than the ticket" do
      fixed = org.ticket_discount_codes.create!(code: " friends ", kind: "fixed", amount_cents: 500)
      expect(fixed.code).to eq("FRIENDS")
      expect([ fixed.discount_cents_for(2_000), fixed.discount_cents_for(300) ]).to eq([ 500, 300 ])

      half = org.ticket_discount_codes.create!(code: "HALF", kind: "percent", percent: 50)
      expect(half.discount_cents_for(2_001)).to eq(1_001)
    end

    it "applies to its show, its production, or the whole org, and only its tiers" do
      general = listing.ticket_tiers.create!(name: "General", price_cents: 2_000)
      vip = listing.ticket_tiers.create!(name: "VIP", price_cents: 4_000)
      code = org.ticket_discount_codes.create!(code: "GA", kind: "fixed", amount_cents: 500, production: production,
                                               ticket_tier_ids: [ general.id ])
      expect([ code.applies_to?(listing, general), code.applies_to?(listing, vip) ]).to eq([ true, false ])

      other_listing = TicketListing.create!(show: create(:show, production: create(:production, organization: org)))
      expect(code.applies_to?(other_listing)).to be(false)
    end

    it "stops working at its limit" do
      code = org.ticket_discount_codes.create!(code: "ONCE", kind: "fixed", amount_cents: 500, max_uses: 1)
      expect(code.usable?).to be(true)
      create(:ticket_order, ticket_listing: listing, ticket_discount_code: code, status: "paid")
      expect(code.usable?).to be(false)
    end
  end

  describe Ticketing::Inventory do
    let(:listing) { TicketListing.create!(show: show, status: "on_sale") }
    let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 3) }
    let!(:vip) { listing.ticket_tiers.create!(name: "VIP", price_cents: 4_000, quantity: 2) }

    def sell(tier, count, status: "valid", order_status: "paid", expires_at: nil)
      order = create(:ticket_order, ticket_listing: listing, status: order_status, expires_at: expires_at)
      count.times { create(:ticket, ticket_order: order, ticket_tier: tier, status: status) }
      order
    end

    it "takes capacity from the tiers' seats when the listing has none of its own" do
      expect(listing.inventory.capacity).to eq(5)
      listing.update!(capacity: 4)
      expect(listing.inventory.capacity).to eq(4)
    end

    it "counts sold seats and seats held by an unpaid order, until the hold runs out" do
      sell(general, 1)
      sell(general, 1, status: "reserved", order_status: "pending", expires_at: 5.minutes.from_now)
      sell(general, 1, status: "reserved", order_status: "pending", expires_at: 1.minute.ago)

      inventory = listing.inventory
      expect([ inventory.sold(tier: general), inventory.held(tier: general) ]).to eq([ 1, 1 ])
      expect(inventory.remaining(tier: general)).to eq(1)
      expect(inventory.remaining).to eq(3)
    end

    it "caps a tier by its own seats and by the room" do
      listing.update!(capacity: 4)
      sell(vip, 2)
      sell(general, 1)
      inventory = listing.inventory
      expect([ inventory.remaining(tier: vip), inventory.remaining(tier: general), inventory.remaining ]).to eq([ 0, 1, 1 ])
      expect(inventory.fits?(general => 1)).to be(true)
      expect(inventory.fits?(general => 2)).to be(false)
    end

    it "is sold out when every tier on sale is" do
      sell(general, 3)
      sell(vip, 2)
      expect(listing.inventory).to be_sold_out
    end

    it "refuses a reservation that no longer fits" do
      sell(general, 3)
      expect { Ticketing::Inventory.reserve!(listing, general => 1) { :never } }.to raise_error(Ticketing::Inventory::SoldOut)
      expect(Ticketing::Inventory.reserve!(listing, vip => 2) { :reserved }).to eq(:reserved)
    end
  end

  describe Ticketing::ListingPayload do
    it "describes the show once, with all-in prices, for every place it appears" do
      listing = TicketListing.create!(show: show, status: "on_sale")
      listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 40)
      listing.ticket_tiers.create!(name: "Industry", price_cents: 1_000, hidden: true, unlock_code: "INDUSTRY")

      payload = Ticketing::ListingPayload.for(listing)
      expect(payload.slice(:title, :production, :organizer)).to eq(title: show.display_name, production: "Improvised Animorphs", organizer: "Stars & Garters")
      expect(payload[:tiers].map { |t| t.slice(:name, :price_cents, :all_in_price_cents, :remaining) })
        .to eq([ { name: "General", price_cents: 2_000, all_in_price_cents: 2_142, remaining: 40 } ])
      expect(payload[:venue][:city]).to eq(show.location.city)
    end
  end
end
