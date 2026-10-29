# frozen_string_literal: true

require "rails_helper"

# PDF tickets (advanced ticketing §7a): one letter page per ticket, with the
# show, when and where, who it's for, the order and its QR code.
RSpec.describe TicketPdf do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:location) { create(:location, organization: org, name: "Stars Lounge") }
  let(:room) { location.location_spaces.create!(name: "Main Stage") }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let(:show) { create(:show, production: production, location: location, location_space: room, date_and_time: Time.zone.local(2027, 3, 13, 20, 0)) }
  let(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let(:premium) { listing.ticket_tiers.create!(name: "Premium", price_cents: 3_000) }
  let(:order) { create(:ticket_order, ticket_listing: listing, status: "paid", buyer_name: "Dana Whitfield") }

  before do
    2.times { create(:ticket, ticket_order: order, ticket_tier: premium) }
    create(:ticket, ticket_order: order, ticket_tier: premium, status: "refunded")
  end

  # Prawn writes each run of text as hex; join them back up.
  def pdf_text(bytes)
    bytes.scan(/<([0-9a-fA-F]+)>/).flatten.map { |hex| [ hex ].pack("H*") }.join
  end

  it "draws a page for each ticket still good, with everything the door and the buyer need" do
    bytes = described_class.new(order).render
    expect(bytes).to start_with("%PDF")
    expect(bytes.scan(%r{/Type /Page\b}).size).to eq(2)

    text = pdf_text(bytes)
    expect(text).to include("STARS & GARTERS", "Boylesque", "Saturday, March 13, 2027", "8:00 PM", "Main Stage", "Stars Lounge",
                            "Dana Whitfield", "Premium", "Order #{order.code}", "Ticket 1 of 2", "Ticket 2 of 2",
                            "Scan at the door", "Tickets by CocoScout")
    expect(text).not_to include("SECTION", "ROW")
    expect(bytes.scan(%r{/Subtype /Image}).size).to eq(2)
  end

  it "puts a ticket's own holder on its page when it has one" do
    order.tickets.where(status: "valid").order(:id).first.update!(holder_name: "Riley Guest")
    expect(pdf_text(described_class.new(order).render)).to include("Riley Guest", "Dana Whitfield")
  end

  it "draws the seat when seating gives the ticket one" do
    pdf = described_class.new(order)
    allow(pdf).to receive(:seat_for).and_return({ section: "Orchestra", row: "C", seat: "14" })
    expect(pdf_text(pdf.render)).to include("SECTION", "Orchestra", "ROW", "SEAT", "14")
  end

  it "says when an order has no tickets left to print" do
    order.tickets.update_all(status: "refunded")
    expect(described_class.new(order).tickets?).to be(false)
  end
end
