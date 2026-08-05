# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Per-event contract services" do
  let(:org) { create(:organization, :pro) }
  let(:contract) { create(:contract, :active, organization: org) }

  let(:oct16) { Time.zone.parse("2026-10-16 19:00") }
  let(:oct17) { Time.zone.parse("2026-10-17 19:00") }

  describe Contract, ".normalize_service_rows" do
    it "builds a per-event line from the checked dates, with hours and the settlement choice" do
      rows = { "0" => {
        "include" => "1", "name" => "Booth Tech", "unit" => "hourly", "per_event" => "1",
        "unit_price" => "25", "direction" => "incoming", "settlement" => "payout_deduction",
        "events" => {
          "0" => { "include" => "1", "starts_at" => oct16.iso8601, "hours" => "2" },
          "1" => { "include" => "0", "starts_at" => oct17.iso8601, "hours" => "3" },
          "2" => { "include" => "1", "starts_at" => (oct17 + 7.days).iso8601, "hours" => "2.5" }
        }
      } }

      line = Contract.normalize_service_rows(rows).first
      expect(line["per_event"]).to be(true)
      expect(line["settlement"]).to eq("payout_deduction")
      expect(line["events"].map { |e| e["hours"] }).to eq([ 2.0, 2.5 ]) # unchecked date dropped
      expect(line["quantity"]).to eq(4.5) # summed hours, for the PDF/summary
    end

    it "falls back to a flat line when per_event is set but no dates were kept" do
      rows = { "0" => {
        "include" => "1", "name" => "Booth Tech", "unit" => "hourly", "per_event" => "1",
        "quantity" => "3", "unit_price" => "25", "direction" => "incoming",
        "events" => { "0" => { "include" => "0", "starts_at" => oct16.iso8601, "hours" => "2" } }
      } }

      line = Contract.normalize_service_rows(rows).first
      expect(line["per_event"]).to be_nil
      expect(line["quantity"]).to eq(3.0)
    end
  end

  describe "#bill_services! with a per-event line" do
    let(:line) do
      { "name" => "Booth Tech", "unit" => "hourly", "unit_price" => 25.0,
        "direction" => "incoming", "settlement" => "payout_deduction", "per_event" => true,
        "quantity" => 4.0,
        "events" => [
          { "starts_at" => oct16.iso8601, "hours" => 2.0 },
          { "starts_at" => oct17.iso8601, "hours" => 2.0 }
        ] }
    end

    it "bills one payment per event — due on the event date, carrying the settlement" do
      expect { contract.bill_services!([ line ]) }
        .to change { contract.contract_payments.count }.by(2)

      first = contract.contract_payments.find_by(due_date: oct16.to_date)
      expect(first.description).to eq("Booth Tech — Oct 16, 2026")
      expect(first.amount.to_f).to eq(50.0) # 2 hrs × $25
      expect(first.settlement_method).to eq("payout_deduction")
      expect(first).to be_direction_incoming
    end

    it "ties each payment to the show on that date when shows exist" do
      production = create(:production, organization: org)
      contract.update!(production: production)
      show = create(:show, production: production, date_and_time: oct16)

      contract.bill_services!([ line ])

      expect(contract.contract_payments.find_by(due_date: oct16.to_date).show_id).to eq(show.id)
      expect(contract.contract_payments.find_by(due_date: oct17.to_date).show_id).to be_nil
    end

    it "bills a flat per-event service at its price per event" do
      flat = line.merge("unit" => "flat", "unit_price" => 100.0,
                        "events" => [ { "starts_at" => oct16.iso8601, "hours" => 1 } ])

      contract.bill_services!([ flat ])
      expect(contract.contract_payments.last.amount.to_f).to eq(100.0)
    end
  end

  describe "#reconcile_service_payments!" do
    it "replaces old per-event payments (dated descriptions) when re-billing" do
      contract.update_draft_step(:services, [
        { "name" => "Booth Tech", "unit" => "hourly", "unit_price" => 25.0,
          "direction" => "incoming", "per_event" => true, "quantity" => 2.0,
          "events" => [ { "starts_at" => oct16.iso8601, "hours" => 2.0 } ] }
      ])
      contract.bill_services!(contract.draft_services)
      expect(contract.contract_payments.where("description LIKE 'Booth Tech —%'").count).to eq(1)

      # Amend down to zero services: the dated payment must go with it.
      contract.reconcile_service_payments!([])
      expect(contract.contract_payments.where("description LIKE 'Booth Tech —%'").count).to eq(0)
    end

    it "never touches a per-event payment that's already been paid" do
      contract.update_draft_step(:services, [
        { "name" => "Booth Tech", "unit" => "hourly", "unit_price" => 25.0,
          "direction" => "incoming", "per_event" => true, "quantity" => 2.0,
          "events" => [ { "starts_at" => oct16.iso8601, "hours" => 2.0 } ] }
      ])
      contract.bill_services!(contract.draft_services)
      paid = contract.contract_payments.find_by(due_date: oct16.to_date)
      paid.update!(status: "paid", paid_date: Date.current)

      contract.reconcile_service_payments!([])
      expect(ContractPayment.exists?(paid.id)).to be(true)
    end
  end

  describe "the amend path keeps the settlement choice" do
    it "no longer resets 'taken out of their payout' to direct on amendment" do
      rows = { "0" => {
        "include" => "1", "name" => "Booth Tech", "unit" => "hourly",
        "quantity" => "3", "unit_price" => "25", "direction" => "incoming",
        "settlement" => "payout_deduction"
      } }
      expect(Contract.normalize_service_rows(rows).first["settlement"]).to eq("payout_deduction")
    end
  end
end
