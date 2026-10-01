# frozen_string_literal: true

require "rails_helper"

# A contract where we sell the tickets can list its shows on CocoScout
# Ticketing: drafts carrying the contract's prices, seats and codes, kept in
# step when the contract is amended, without ever changing what a buyer bought.
RSpec.describe TicketListingSync do
  let(:org) { create(:organization, :pro) }
  let(:location) { create(:location, organization: org) }
  let(:nights) { [ 10.days.from_now.change(hour: 19, min: 30), 17.days.from_now.change(hour: 19, min: 30) ] }
  let(:rehearsal_at) { 8.days.from_now.change(hour: 18) }

  def booking(time, type = "show")
    { "location_id" => location.id, "starts_at" => time.iso8601, "ends_at" => (time + 3.hours).iso8601, "event_type" => type }
  end

  def ticketing(list: true, general_price: 20.0, general_seats: 60)
    {
      "tiers" => [ { "name" => "General", "price" => general_price, "quantity" => general_seats },
                   { "name" => "VIP", "price" => 35.0 } ],
      "discounts" => [ { "code" => "friends", "amount" => 5, "amount_type" => "fixed",
                         "applies_to" => "specific", "tier_names" => [ "General" ] } ],
      "list_on_cocoscout" => list
    }
  end

  def build_contract(list: true)
    create(:contract, organization: org, contractor_name: "Improvised Animorphs",
                      contract_start_date: rehearsal_at.to_date, contract_end_date: nights.last.to_date,
                      draft_data: {
                        "bookings" => nights.map { |t| booking(t) } + [ booking(rehearsal_at, "rehearsal") ],
                        "payments" => [],
                        "payment_structure" => "revenue_share",
                        "payment_config" => { "who_sells_tickets" => "org", "settlement_basis" => "revenue_share",
                                              "revenue_our_share" => 30, "revenue_settlement" => "per_event" },
                        "ticketing" => ticketing(list: list)
                      })
  end

  def listings_for(contract)
    TicketListing.where(contract: contract).joins(:show).order("shows.date_and_time").to_a
  end

  it "lists each show as a draft with the contract's prices, seats and codes, and skips the rehearsal" do
    contract = build_contract
    contract.activate!

    listings = listings_for(contract)
    expect(listings.map { |l| [ l.show.event_type, l.status ] }).to eq([ %w[show draft], %w[show draft] ])
    expect(listings.first.ticket_tiers.map { |t| [ t.name, t.price_cents, t.quantity ] })
      .to eq([ [ "General", 2_000, 60 ], [ "VIP", 3_500, nil ] ])

    code = listings.first.ticket_discount_codes.sole
    expect([ code.code, code.kind, code.amount_cents ]).to eq([ "FRIENDS", "fixed", 500 ])
    expect(code.ticket_tier_ids).to eq([ listings.first.ticket_tiers.find_by(name: "General").id ])
  end

  it "does nothing unless the contract asked to sell here and the org has ticketing" do
    contract = build_contract(list: false)
    contract.activate!
    expect(TicketListing.count).to eq(0)

    contract.update_draft_step(:ticketing, ticketing(list: true))
    org.update!(comped_indefinitely: false)
    expect(described_class.for_contract(contract.reload)).to eq([])
    expect(TicketListing.count).to eq(0)
  end

  it "follows an amendment without touching what buyers bought" do
    contract = build_contract
    contract.activate!
    listing = listings_for(contract).first
    general = listing.ticket_tiers.find_by(name: "General")
    vip = listing.ticket_tiers.find_by(name: "VIP")
    order = create(:ticket_order, ticket_listing: listing, status: "paid")
    create_list(:ticket, 40, ticket_order: order, ticket_tier: general)
    create(:ticket, ticket_order: order, ticket_tier: vip)
    listing.ticket_discount_codes.create!(organization: org, code: "CAST", kind: "percent", percent: 50)

    amended = ticketing(general_price: 25.0, general_seats: 30)
    amended["tiers"] = amended["tiers"].reject { |t| t["name"] == "VIP" }
    amended["discounts"].first["amount"] = 8
    contract.apply_amendment!({ "ticketing" => amended })

    expect([ general.reload.price_cents, general.quantity ]).to eq([ 2_500, 40 ]) # never below the 40 sold
    expect(vip.reload.archived_at).to be_present                                 # sold, so kept for its buyer
    expect(listing.ticket_discount_codes.find_by(code: "FRIENDS").amount_cents).to eq(800)
    expect(listing.ticket_discount_codes.find_by(code: "CAST")).to be_present     # the manager's own code stays
    expect(listings_for(contract).last.ticket_tiers.map(&:name)).to eq([ "General" ]) # unsold VIP just goes
  end

  it "drops a draft whose show left the contract, but keeps one people bought for" do
    contract = build_contract
    contract.activate!
    first, second = listings_for(contract)
    create(:ticket_order, ticket_listing: second, status: "paid")

    first.show.update!(canceled: true)
    second.show.update!(canceled: true)
    described_class.for_contract(contract)

    expect(TicketListing.exists?(first.id)).to be(false)
    expect(TicketListing.exists?(second.id)).to be(true)
  end
end
