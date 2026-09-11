# frozen_string_literal: true

require "rails_helper"

# Ticket sales are entered one line per source. The lines are the truth;
# show_financials.ticket_count and .ticket_revenue are rollups of them, kept
# because roughly thirty places read those two columns — every contract
# settlement, the per-ticket payout methods, the reports.
RSpec.describe "Ticket sales lines", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production, date_and_time: Time.zone.local(2026, 9, 18, 20)) }
  let(:financials) { show.create_show_financials!(revenue_type: "ticket_sales") }

  let!(:eventbrite) { org.ticket_sources.create!(name: "Eventbrite", position: 1) }
  let!(:door) { org.ticket_sources.create!(name: "At the door", position: 2) }

  it "rolls the lines up into the cached columns" do
    financials.ticket_sales_lines.create!(ticket_source: eventbrite, tickets_sold: 40, amount: 400)
    financials.ticket_sales_lines.create!(ticket_source: door, tickets_sold: 12, amount: 144)

    expect(financials.reload.ticket_count).to eq(52)
    expect(financials.ticket_revenue).to eq(544)
    expect(financials.total_revenue).to eq(544)
  end

  it "keeps the rollup right when a line changes or goes away" do
    a = financials.ticket_sales_lines.create!(ticket_source: eventbrite, tickets_sold: 40, amount: 400)
    b = financials.ticket_sales_lines.create!(ticket_source: door, tickets_sold: 12, amount: 144)

    a.update!(tickets_sold: 45, amount: 450)
    expect(financials.reload.ticket_count).to eq(57)
    expect(financials.ticket_revenue).to eq(594)

    b.destroy!
    expect(financials.reload.ticket_count).to eq(45)
    expect(financials.ticket_revenue).to eq(450)
  end

  it "updates the in-memory object, not just the row" do
    # ShowFinancialsController#update calls ContractPaymentSyncService straight
    # after saving, and that reads total_revenue off this very object.
    financials.ticket_sales_lines.create!(ticket_source: eventbrite, tickets_sold: 10, amount: 100)

    expect(financials.ticket_revenue).to eq(100)
    expect(financials.total_revenue).to eq(100)
  end

  it "leaves a financials row with no lines exactly as it was" do
    legacy = show.show_financials || financials
    legacy.update!(ticket_count: 33, ticket_revenue: 330)

    expect(legacy.ticket_sales_lines).to be_empty
    legacy.recalculate_ticket_totals!

    expect(legacy.reload.ticket_count).to eq(33)
    expect(legacy.ticket_revenue).to eq(330)
  end

  describe "a line whose source is gone or was never set" do
    it "still says something sensible" do
      line = financials.ticket_sales_lines.create!(tickets_sold: 5, amount: 50)
      expect(line.source_name).to eq("Ticket sales")

      line.update!(ticket_source: eventbrite)
      expect(line.source_name).to eq("Eventbrite")
    end

    it "survives its source being archived" do
      line = financials.ticket_sales_lines.create!(ticket_source: eventbrite, tickets_sold: 5, amount: 50)
      eventbrite.archive!

      expect(line.reload.source_name).to eq("Eventbrite")
      expect(org.ticket_sources.active).not_to include(eventbrite)
    end
  end

  describe "TicketSource" do
    it "won't take two of the same name in one org" do
      dupe = org.ticket_sources.build(name: "eventbrite")
      expect(dupe).not_to be_valid
    end

    it "lets another org use the same name" do
      other = create(:organization, :pro)
      expect(other.ticket_sources.build(name: "Eventbrite")).to be_valid
    end

    it "keeps its lines when it's archived, and can come back" do
      financials.ticket_sales_lines.create!(ticket_source: door, tickets_sold: 3, amount: 30)

      door.archive!
      expect(door).to be_archived
      expect(financials.reload.ticket_sales_lines.count).to eq(1)

      door.restore!
      expect(door).not_to be_archived
      expect(org.ticket_sources.active).to include(door)
    end
  end
end
