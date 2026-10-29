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

  def read(text, **options)
    described_class.parse(text, listing: listing, default_tier: general, **options)
  end

  def rows(paste) = paste.guests.map { |g| [ g.name, g.email, g.tier.name, g.quantity ] }

  it "reads a pasted guest list, every way it's pasted" do
    paste = read(<<~LIST)
      Dana Scully, Dana@Example.com, 2
      Fox Mulder\tfox@example.com
      Walter Skinner, 3, VIP
      Monica Reyes <monica@example.com>
      John Doggett <john@example.com>, 2
      Rosa\tDelgado\trosa@example.com\t4
      tkwan@example.com
      "Kersh, Alvin",alvin@example.com

    LIST
    expect(rows(paste)).to eq([
      [ "Dana Scully", "dana@example.com", "General", 2 ],
      [ "Fox Mulder", "fox@example.com", "General", 1 ],
      [ "Walter Skinner", nil, "VIP", 3 ],
      [ "Monica Reyes", "monica@example.com", "General", 1 ],
      [ "John Doggett", "john@example.com", "General", 2 ],
      [ "Rosa Delgado", "rosa@example.com", "General", 4 ],
      [ "tkwan@example.com", "tkwan@example.com", "General", 1 ],
      [ "Kersh, Alvin", "alvin@example.com", "General", 1 ]
    ])
    expect(paste.problems).to be_empty
  end

  it "skips a CSV's header row, and only a first line that looks like one" do
    paste = read("Name,Email,Tickets\nDana Scully,dana@example.com,2\nName,name@example.com\n")
    expect(rows(paste)).to eq([ [ "Dana Scully", "dana@example.com", "General", 2 ], [ "Name", "name@example.com", "General", 1 ] ])

    expect(rows(read("First Name\tLast Name\tEmail Address\nDana\tScully\tdana@example.com"))).to eq([ [ "Dana Scully", "dana@example.com", "General", 1 ] ])
    expect(rows(read("Dana Scully, 2"))).to eq([ [ "Dana Scully", nil, "General", 2 ] ])
  end

  it "leaves out a repeated email and keeps the lines it can't read as problems" do
    paste = read(<<~LIST)
      Dana Scully, dana@example.com
      Dana again, DANA@example.com, 3
      Fox, fox@example
      Two, a@example.com, b@example.com
      Skinner, 0
      ,,,
    LIST
    expect(rows(paste)).to eq([ [ "Dana Scully", "dana@example.com", "General", 1 ] ])
    expect(paste.repeats.map { |r| [ r.line, r.reason ] }).to eq([ [ 2, "Same email as line 1, so left out." ] ])
    expect(paste.problems.map { |p| [ p.line, p.reason ] }).to eq([
      [ 3, "fox@example isn't an email address." ],
      [ 4, "More than one email on this line." ],
      [ 5, "0 isn't a number of tickets to give." ]
    ])
  end

  it "needs an email on every line when they're all to be emailed" do
    paste = read("Dana Scully, dana@example.com\nWalter Skinner", email_them: true)
    expect(rows(paste)).to eq([ [ "Dana Scully", "dana@example.com", "General", 1 ] ])
    expect(paste.problems.map(&:reason)).to eq([ "No email to send Walter Skinner their tickets." ])
  end

  it "previews a list against the comps, seats and allowance left" do
    preview = described_class.preview(listing, "A, 2\nB, a@example.com", tier: general, email_them: false, allowance_left: 5)
    expect([ preview.ready?, preview.total, preview.seats.map { |s| [ s[:tier].name, s[:asked], s[:left] ] } ]).to eq([ true, 3, [ [ "General", 3, 5 ] ] ])

    short = described_class.preview(listing, "A, 4\nB, 2", tier: general, email_them: false, allowance_left: 5)
    expect(short.ready?).to be(false)
    expect(short.blockers).to eq([ "You can give 5 more comps for this date, and this list is 6.", "General has 5 seats left, and this list needs 6." ])

    expect(described_class.preview(listing, "A", tier: nil, email_them: false).stopper).to eq("Pick a ticket type.")
    expect(described_class.preview(listing, "", tier: general, email_them: false).stopper).to eq("Paste at least one person, one per line.")
  end

  it "gives free tickets that take seats and arrive by email" do
    guests = read("Dana Scully, dana@example.com, 2\nWalter Skinner").guests

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
    guests = read("A, 3\nB, 3").guests
    expect { described_class.give!(listing, guests, by: manager) }.to raise_error(described_class::Error, /\AGeneral has only \d+ seats? left\.\z/)
    expect(TicketOrder.count).to eq(0)
  end

  it "refuses rows it can't use, and a canceled show" do
    bad = [ described_class::Guest.new(name: "Dana", email: "dana@@example", tier: general, quantity: 1) ]
    expect { described_class.give!(listing, bad, by: manager) }.to raise_error(described_class::Error, /Check Dana/)
    expect { described_class.give!(listing, [], by: manager) }.to raise_error(described_class::Error, /at least one/)

    listing.update!(status: "canceled")
    ok = read("Dana").guests
    expect { described_class.give!(listing, ok, by: manager) }.to raise_error(described_class::Error, /canceled/)
  end
end
