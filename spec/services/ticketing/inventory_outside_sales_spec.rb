# frozen_string_literal: true

require "rails_helper"

# Tickets sold on other sites (Tim, 2026-10-06): typed on a show's page per
# ticket type and site, they take that type's seats here ("ten VIP on Ticket
# Tailor is different from ten General"), so a show listed in two places
# never oversells; their sums feed the show's financials rows.
RSpec.describe Ticketing::Inventory, "with tickets sold elsewhere" do
  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50) }
  let!(:vip) { listing.ticket_tiers.create!(name: "VIP", price_cents: 3_500, quantity: 10) }
  let(:ticket_tailor) { org.ticket_sources.create!(name: "Ticket Tailor") }
  let(:eventbrite) { org.ticket_sources.create!(name: "Eventbrite") }

  it "takes each type's seats, says where they went, and feeds the financials" do
    TicketOutsideSales.record!(listing, { ticket_tailor.id.to_s => { vip.id.to_s => { "tickets" => "4", "amount" => "$140" }, general.id.to_s => { "tickets" => "10", "amount" => "" } },
                                          eventbrite.id.to_s => { general.id.to_s => { "tickets" => "5", "amount" => "100" } } })

    inventory = listing.inventory
    expect([ inventory.outside_sold, inventory.remaining, inventory.remaining(tier: general), inventory.remaining(tier: vip) ]).to eq([ 19, 41, 35, 6 ])
    expect(inventory.outside_words(tier: general)).to eq("5 on Eventbrite and 10 on Ticket Tailor")
    expect(inventory.fits?({ vip => 6 })).to be(true)
    expect(inventory.fits?({ vip => 7 })).to be(false)

    lines = listing.show.show_financials.ticket_sales_lines.index_by(&:ticket_source_id)
    expect(lines[ticket_tailor.id].attributes.values_at("tickets_sold", "amount")).to eq([ 14, 140.to_d ])
    expect(lines[eventbrite.id].attributes.values_at("tickets_sold", "amount")).to eq([ 5, 100.to_d ])
    expect(listing.show.show_financials.ticket_count).to eq(19)
    expect(TicketOutsideSales.fed_source_ids(listing.show)).to contain_exactly(ticket_tailor.id, eventbrite.id)

    # Cleared (or left out of the form), a site's rows and its financials line go; the other site's stay.
    TicketOutsideSales.record!(listing, { ticket_tailor.id.to_s => { vip.id.to_s => { "tickets" => "", "amount" => "" } } })
    expect(listing.ticket_outside_sales.count).to eq(1)
    expect(listing.show.show_financials.reload.ticket_sales_lines.pluck(:ticket_source_id)).to eq([ eventbrite.id ])
    expect(listing.inventory.remaining(tier: vip)).to eq(10)
  end

  it "sells a type out from elsewhere alone, and ignores tiers and sites that aren't this show's" do
    TicketOutsideSales.record!(listing, { ticket_tailor.id.to_s => { vip.id.to_s => { "tickets" => "10" } } })
    expect(listing.inventory.remaining(tier: vip)).to eq(0)
    expect(listing.inventory.sold_out?).to be(false)

    theirs = create(:organization).ticket_sources.create!(name: "Theirs")
    other_tier = create(:ticket_listing, organization: org).ticket_tiers.create!(name: "General", price_cents: 1_000, quantity: 5)
    TicketOutsideSales.record!(listing, { theirs.id.to_s => { vip.id.to_s => { "tickets" => "3" } },
                                          ticket_tailor.id.to_s => { vip.id.to_s => { "tickets" => "10" }, other_tier.id.to_s => { "tickets" => "3" } } })
    expect(listing.ticket_outside_sales.pluck(:ticket_source_id, :ticket_tier_id, :tickets_sold)).to eq([ [ ticket_tailor.id, vip.id, 10 ] ])
  end
end
