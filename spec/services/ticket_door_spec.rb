# frozen_string_literal: true

require "rails_helper"

# The door on show night: scans, the wrong-ticket cases, whole parties,
# undoing a mistake, and cash sales and comps at the door.
RSpec.describe TicketDoor do
  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10) }
  let(:door_person) { create(:user) }
  let(:door) { described_class.new(listing, door_person) }

  def sold_order(count = 2)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    TicketOrderSettlement.settle!(order)
    order.reload
  end

  describe "#check_in" do
    it "admits a ticket from its QR link, its bare code, or another site's barcode" do
      order = sold_order(3)
      first, second, third = order.tickets.order(:id).to_a
      third.update!(external_barcode: "EB-123")

      expect(door.check_in("https://cocoscout.com/tickets/v/#{first.code}").kind).to eq(:admitted)
      expect(door.check_in(" #{second.code} ").kind).to eq(:admitted)
      expect(door.check_in("EB-123").kind).to eq(:admitted)
      expect(order.tickets.reload.pluck(:status).uniq).to eq([ "checked_in" ])
      expect(first.reload.checked_in_by).to eq(door_person)
    end

    it "says when a ticket was already used" do
      ticket = sold_order(1).tickets.sole
      door.check_in(ticket.code)
      result = door.check_in(ticket.code)
      expect(result.kind).to eq(:already)
      expect(result.message).to start_with("Already checked in at")
    end

    it "turns away a ticket for another show, a refunded ticket, and a made-up code" do
      other_listing = create(:ticket_listing, organization: org)
      other_tier = other_listing.ticket_tiers.create!(name: "General", price_cents: 1_000)
      other = TicketCheckout.start!(listing: other_listing, quantities: { other_tier.id.to_s => "1" })
      TicketOrderSettlement.settle!(other)
      refunded = sold_order(1).tickets.sole
      refunded.update!(status: "refunded")

      expect(door.check_in(other.tickets.sole.code).kind).to eq(:wrong_show)
      expect(door.check_in(refunded.code).kind).to eq(:not_valid)
      expect(door.check_in("nope").kind).to eq(:not_found)
      expect(door.check_in("").kind).to eq(:not_found)
      expect(other.tickets.sole.reload.status).to eq("valid")
    end

    it "never admits one ticket twice, even from two phones at once" do
      ticket = sold_order(1).tickets.sole
      phone_a = described_class.new(listing, door_person)
      phone_b = described_class.new(listing, create(:user))
      kinds = [ phone_a.admit(Ticket.find(ticket.id)), phone_b.admit(Ticket.find(ticket.id)) ].map(&:kind)
      expect(kinds).to contain_exactly(:admitted, :already)
    end
  end

  it "checks in a whole party, skipping anyone already in" do
    order = sold_order(4)
    door.check_in(order.tickets.first.code)
    results = door.check_in_order(order)
    expect(results.map(&:kind)).to eq(%i[admitted admitted admitted])
    expect(door.counts).to eq(checked_in: 4, sold: 4, capacity: 10)
  end

  describe "#undo" do
    it "lets door staff undo their own check-in for a couple of minutes, and managers any time" do
      ticket = sold_order(1).tickets.sole
      door.check_in(ticket.code)
      expect(door.undo(ticket.reload)).to be(true)
      expect(ticket.reload.status).to eq("valid")

      door.check_in(ticket.code)
      travel 3.minutes do
        expect(door.undo(ticket.reload)).to be(false)
        expect(described_class.new(listing, create(:user)).undo(ticket, manager: false)).to be(false)
        expect(described_class.new(listing, create(:user)).undo(ticket, manager: true)).to be(true)
      end
    end
  end

  describe "#sell" do
    it "records cash at the door: no fees, checked in, on the show's financials and in the books as door cash" do
      TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
      order = door.sell({ general.id.to_s => "2" }, kind: "cash", buyer_name: "  Walk  Up ")

      expect([ order.channel, order.money_path, order.status, order.buyer_name ]).to eq([ "door_cash", "cash", "paid", "Walk Up" ])
      expect([ order.platform_fee_cents, order.processing_cents, order.tax_cents, order.total_cents ]).to eq([ 0, 0, 410, 4_410 ])
      expect(order.tickets.pluck(:status).uniq).to eq([ "checked_in" ])
      expect(OrgCashEntry.where(source: order)).to be_empty

      expect(ChartOfAccounts.account(org, :door_cash).natural_balance_cents).to eq(4_410)
      expect(ChartOfAccounts.account(org, :ticket_income).natural_balance_cents).to eq(4_000)
      expect(ChartOfAccounts.account(org, :tax_to_remit).natural_balance_cents).to eq(410)
      expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)

      line = listing.show.reload.show_financials.ticket_sales_lines.sole
      expect([ line.tickets_sold, line.amount.to_f ]).to eq([ 2, 40.0 ])
    end

    it "comps for free: nothing in the books, but they count and they're in" do
      order = door.sell({ general.id.to_s => "2" }, kind: "comp")
      expect([ order.channel, order.money_path, order.total_cents ]).to eq([ "comp", "none", 0 ])
      expect(JournalEntry.where(source: order)).to be_empty
      expect(door.counts).to eq(checked_in: 2, sold: 2, capacity: 10)
    end

    it "won't sell past the seats, or for a canceled show" do
      sold_order(9)
      expect { door.sell({ general.id.to_s => "2" }, kind: "cash") }.to raise_error(TicketCheckout::Error, /more than the seats left/)
      expect { door.sell({}, kind: "cash") }.to raise_error(TicketCheckout::Error, /at least one/)

      listing.update!(status: "canceled")
      expect { door.sell({ general.id.to_s => "1" }, kind: "cash") }.to raise_error(TicketCheckout::Error, /canceled/)
    end
  end
end
