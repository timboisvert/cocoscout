# frozen_string_literal: true

require "rails_helper"

# Dated passes (Tim, 2026-10-05): "Twilight: Breaking Dawn 1 and 2 together
# for less", or Boylesque and Laugh Along Live on one night. Buying one takes
# a seat at every show, in one checkout with one payment, and each show's
# ticket carries its share of the price: by regular price (the default),
# evenly, or shares the manager types.
RSpec.describe TicketPass do
  let(:org) { create(:organization, :pro) }
  let(:part_one) { create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: 2.weeks.from_now)) }
  let(:part_two) { create(:ticket_listing, organization: org, show: create(:show, production: part_one.production, date_and_time: 2.weeks.from_now + 1.day)) }
  let!(:one_general) { part_one.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10) }
  let!(:two_general) { part_two.ticket_tiers.create!(name: "General", price_cents: 4_000, quantity: 10) }
  let(:pass) do
    org.ticket_passes.create!(name: "Twilight Double Feature", price_cents: 4_500, status: "on_sale",
                              pass_shows_attributes: [ { ticket_tier_id: two_general.id }, { ticket_tier_id: one_general.id } ])
  end

  it "splits the price by regular price by default, evenly, or as typed, always adding up" do
    expect(pass.rows.map(&:ticket_listing)).to eq([ part_one, part_two ])
    expect(pass.shares).to eq([ 1_500, 3_000 ])
    pass.update!(split: "even")
    expect(pass.shares).to eq([ 2_250, 2_250 ])

    pass.pass_shows.find_by(ticket_listing: part_one).update!(share_cents: 1_000)
    pass.pass_shows.find_by(ticket_listing: part_two).update!(share_cents: 3_000)
    pass.reload.split = "custom"
    expect(pass).not_to be_valid
    expect(pass.errors.full_messages.first).to include("add up to $40.00, not the pass price of $45.00")
  end

  it "takes a seat at every show, each ticket carrying its show's share and the pass" do
    order = TicketCheckout.start_pass!(pass: pass, quantity: 2)
    purchase = order.ticket_purchase
    first, second = purchase.ticket_orders.to_a

    expect([ first.ticket_listing, second.ticket_listing ]).to eq([ part_one, part_two ])
    expect(first.tickets.pluck(:price_cents, :discount_cents, :ticket_pass_id)).to eq([ [ 2_000, 500, pass.id ] ] * 2)
    expect(second.tickets.pluck(:price_cents, :discount_cents)).to eq([ [ 4_000, 1_000 ] ] * 2)
    expect([ part_one.inventory.remaining(tier: one_general), part_two.inventory.remaining(tier: two_general) ]).to eq([ 8, 8 ])
    expect(purchase.total_cents).to eq(pass.all_in_price_cents * 2 - TicketPricing::PROCESSING_FIXED_CENTS)
    expect(pass.all_in_price_cents).to be < pass.separately_all_in_cents
  end

  it "settles each show with its share, which is what its financials and splits see" do
    order = TicketCheckout.start_pass!(pass: pass, quantity: 1)
    TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_pass")

    expect(OrgCashEntry.where(entry_type: "ticket_sale").order(:id).pluck(:amount_cents)).to eq([ 1_500, 3_000 ])
    expect(part_one.show.reload.show_financials.ticket_sales_lines.pluck(:tickets_sold, :amount)).to eq([ [ 1, 15.to_d ] ])
    expect(part_two.show.reload.show_financials.ticket_sales_lines.pluck(:amount)).to eq([ 30.to_d ])
    expect(pass.sold_count).to eq(1)
  end

  it "holds nothing when one show hasn't the seats, and respects the cap" do
    two_general.update!(quantity: 1)
    expect { TicketCheckout.start_pass!(pass: pass, quantity: 2) }.to raise_error(TicketCheckout::Error, /doesn't have enough seats/)
    expect(TicketOrder.count).to eq(0)
    expect(part_one.inventory.remaining(tier: one_general)).to eq(10)

    pass.update!(max_sold: 1)
    expect(pass.remaining).to eq(1)
    expect { TicketCheckout.start_pass!(pass: pass, quantity: 2) }.to raise_error(TicketCheckout::Error, /aren't that many passes left/)
  end

  it "stops selling when its first show's online sales close, or a show is canceled" do
    expect(pass).to be_selling
    travel_to(part_one.off_sale_at + 1.minute) { expect(pass).not_to be_selling }
    part_two.show.update!(canceled: true)
    expect(pass.reload).not_to be_selling
  end

  it "only takes a show's own plain ticket type, from the same organization" do
    bundle = part_one.ticket_tiers.create!(name: "4-pack", price_cents: 7_000, admits: 4, bundle_of: one_general)
    elsewhere = create(:ticket_listing).ticket_tiers.create!(name: "General", price_cents: 1_000, quantity: 5)

    expect(pass.pass_shows.build(ticket_tier: bundle)).not_to be_valid
    expect(pass.pass_shows.build(ticket_tier: elsewhere)).not_to be_valid
  end
end
