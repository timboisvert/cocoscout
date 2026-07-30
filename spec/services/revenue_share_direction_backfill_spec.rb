# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevenueShareDirectionBackfill do
  let(:org) { create(:organization) }

  def we_sell_contract(payments:, our_share: 60)
    create(:contract, organization: org,
      draft_data: {
        "payment_structure" => "revenue_share",
        "payment_config" => { "who_sells_tickets" => "org", "revenue_our_share" => our_share },
        "payments" => payments
      })
  end

  def rev_row(description, direction: "incoming")
    { "source" => "Revenue share", "description" => description, "amount" => 0, "amount_tbd" => true, "direction" => direction }
  end

  describe ".run" do
    it "flips we-sell settlement rows to outgoing and relabels the share as 'to them'" do
      contract = we_sell_contract(our_share: 60, payments: [
        rev_row("Week 1 — 60% to us"),
        rev_row("Week 2 — 60% to us")
      ])

      result = described_class.run

      rows = contract.reload.draft_payments
      expect(rows.map { |r| r["direction"] }).to all(eq("outgoing"))
      expect(rows.map { |r| r["description"] }).to eq([ "Week 1 — 40% to them", "Week 2 — 40% to them" ])
      expect(result.contracts_fixed).to eq(1)
      expect(result.draft_rows_fixed).to eq(2)
    end

    it "flips the minimum-guarantee row too, keeping its label" do
      contract = we_sell_contract(payments: [
        rev_row("Aug 2026 — 60% to us"),
        { "source" => "Minimum guarantee", "description" => "Minimum guarantee", "amount" => 500, "direction" => "incoming" }
      ])

      described_class.run

      guarantee = contract.reload.draft_payments.find { |r| r["source"] == "Minimum guarantee" }
      expect(guarantee["direction"]).to eq("outgoing")
      expect(guarantee["description"]).to eq("Minimum guarantee")
    end

    it "leaves contractor-sells deals (already 'they pay us') untouched" do
      contract = create(:contract, organization: org,
        draft_data: {
          "payment_structure" => "revenue_share",
          "payment_config" => { "who_sells_tickets" => "contractor", "revenue_our_share" => 60 },
          "payments" => [ rev_row("Week 1 — 60% to us") ]
        })

      expect(described_class.run.contracts_fixed).to eq(0)
      expect(contract.reload.draft_payments.first["direction"]).to eq("incoming")
    end

    it "never touches hand-added (extra) payments" do
      contract = we_sell_contract(payments: [
        rev_row("Week 1 — 60% to us"),
        { "description" => "Cleaning deposit", "amount" => 100, "direction" => "incoming", "extra" => true }
      ])

      described_class.run

      extra = contract.reload.draft_payments.find { |r| r["extra"] }
      expect(extra["direction"]).to eq("incoming")
    end

    it "fixes still-pending materialized contract_payments on active contracts" do
      contract = we_sell_contract(our_share: 60, payments: [ rev_row("Week 1 — 60% to us") ])
      pending = create(:contract_payment, contract: contract, direction: "incoming",
        amount: 0, amount_tbd: true, description: "Week 1 — 60% to us", status: "pending")
      paid = create(:contract_payment, :paid, contract: contract, direction: "incoming",
        amount: 0, amount_tbd: true, description: "Week 2 — 60% to us")

      described_class.run

      expect(pending.reload.direction).to eq("outgoing")
      expect(pending.description).to eq("Week 1 — 40% to them")
      # Already-settled rows are history — left alone.
      expect(paid.reload.direction).to eq("incoming")
    end

    it "is idempotent" do
      contract = we_sell_contract(payments: [ rev_row("Week 1 — 60% to us") ])

      described_class.run
      second = described_class.run

      expect(second.contracts_fixed).to eq(0)
      expect(contract.reload.draft_payments.first["description"]).to eq("Week 1 — 40% to them")
    end

    it "reports counts without writing under dry_run" do
      contract = we_sell_contract(payments: [ rev_row("Week 1 — 60% to us") ])

      result = described_class.run(dry_run: true)

      expect(result.contracts_fixed).to eq(1)
      expect(result.draft_rows_fixed).to eq(1)
      expect(contract.reload.draft_payments.first["direction"]).to eq("incoming")
    end
  end
end
