# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutRulesBuilder do
  describe ".build" do
    it "builds a share-of-the-night calculation with house, expenses and someone's cut" do
      rules = described_class.build(
        "method" => "equal", "expenses_first" => "1", "house_percentage" => "40",
        "individual_allocations" => { "0" => { "person_id" => "12", "percentage" => "5", "label" => "Producer" } }
      )

      expect(rules["distribution"]).to eq("method" => "equal")
      expect(rules["allocation"]).to eq([
        { "type" => "expenses_first" },
        { "type" => "percentage", "value" => 40.0, "label" => "House take" },
        { "type" => "percentage", "value" => 5.0, "person_id" => 12, "label" => "Producer" },
        { "type" => "remainder", "label" => "Performer pool" }
      ])
      expect(rules["performer_overrides"]).to eq({})
    end

    it "keeps allocation empty for approaches that never touch the pool" do
      rules = described_class.build("method" => "flat_fee", "house_percentage" => "40",
                                    "distribution" => { "flat_amount" => "60" })
      expect(rules["allocation"]).to eq([])
      expect(rules["distribution"]).to eq("method" => "flat_fee", "flat_amount" => 60.0)
    end

    it "round-trips not paid" do
      expect(described_class.build("method" => "no_pay")["distribution"]).to eq("method" => "no_pay")
    end

    it "builds per-ticket with a minimum, and per-act in each of its three shapes" do
      expect(described_class.build("method" => "per_ticket_guaranteed",
                                   "distribution" => { "per_ticket_rate" => "2.5", "minimum" => "30" })["distribution"])
        .to eq("method" => "per_ticket_guaranteed", "per_ticket_rate" => 2.5, "minimum" => 30.0)

      expect(described_class.build("method" => "per_act", "distribution" => { "act_mode" => "simple", "per_act_rate" => "25" })["distribution"])
        .to eq("method" => "per_act", "act_mode" => "simple", "per_act_rate" => 25.0)

      expect(described_class.build("method" => "per_act", "distribution" => { "act_mode" => "schedule", "act_rates" => [ "75", "50" ], "additional_act_rate" => "" })["distribution"])
        .to eq("method" => "per_act", "act_mode" => "schedule",
               "act_rates" => [ { "act" => 1, "amount" => 75.0 }, { "act" => 2, "amount" => 50.0 } ],
               "additional_act_rate" => nil)

      expect(described_class.build("method" => "per_act", "distribution" => { "act_mode" => "tiers", "tiers" => { "0" => { "acts" => "2", "amount" => "50" }, "1" => { "acts" => "1", "amount" => "25" }, "2" => { "acts" => "", "amount" => "9" } } })["distribution"])
        .to eq("method" => "per_act", "act_mode" => "tiers",
               "tiers" => [ { "acts" => 1, "amount" => 25.0 }, { "acts" => 2, "amount" => 50.0 } ])
    end

    it "keeps the beyond-the-table rate on a tiers table, and leaves it out when blank" do
      with_rate = described_class.build("method" => "per_act", "distribution" => {
        "act_mode" => "tiers", "tiers" => { "0" => { "acts" => "1", "amount" => "75" }, "1" => { "acts" => "2", "amount" => "125" } }, "additional_act_rate" => "50"
      })["distribution"]
      expect(with_rate).to eq("method" => "per_act", "act_mode" => "tiers",
                              "tiers" => [ { "acts" => 1, "amount" => 75.0 }, { "acts" => 2, "amount" => 125.0 } ],
                              "additional_act_rate" => 50.0)

      without = described_class.build("method" => "per_act", "distribution" => {
        "act_mode" => "tiers", "tiers" => { "0" => { "acts" => "1", "amount" => "75" } }, "additional_act_rate" => ""
      })["distribution"]
      expect(without).not_to have_key("additional_act_rate")
    end

    it "treats an unknown act mode as a tiers table" do
      expect(described_class.build("method" => "per_act", "distribution" => { "tiers" => [ { "acts" => "1", "amount" => "20" } ] })["distribution"]["act_mode"]).to eq("tiers")
    end

    it "falls back to equal for an unknown approach" do
      expect(described_class.build("method" => "magic")["distribution"]["method"]).to eq("equal")
    end
  end

  describe ".override" do
    let(:base) do
      { "allocation" => [ { "type" => "percentage", "value" => 50.0, "label" => "House take" }, { "type" => "remainder" } ],
        "distribution" => { "method" => "shares", "default_shares" => 1.0 },
        "performer_overrides" => { "7" => { "shares" => 2.0 } } }
    end

    it "changes only what was sent and keeps the rest of the calculation, method included" do
      rules = described_class.override(base, "distribution" => { "method" => "flat_fee", "default_shares" => "1.5" })

      expect(rules["distribution"]).to eq("method" => "shares", "default_shares" => 1.5)
      expect(rules["allocation"]).to eq(base["allocation"])
      expect(rules["performer_overrides"]).to eq(base["performer_overrides"])
    end

    it "sets exact amounts for specific people, guests included, and drops blanks" do
      rules = described_class.override(base, "performer_overrides" => {
        "7" => { "flat_amount" => "100" }, "guest_9" => { "flat_amount" => "40" }, "8" => { "flat_amount" => "" }
      })

      expect(rules["performer_overrides"]).to eq("7" => { "flat_amount" => 100.0 }, "guest_9" => { "flat_amount" => 40.0 })
      expect(rules["distribution"]).to eq(base["distribution"])
    end

    it "lets a pool approach change the house take tonight, but ignores it for a flat approach" do
      rules = described_class.override(base, "house_percentage" => "30", "expenses_first" => "1")
      expect(rules["allocation"]).to include({ "type" => "expenses_first" }, { "type" => "percentage", "value" => 30.0, "label" => "House take" })

      flat = { "allocation" => [], "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 } }
      expect(described_class.override(flat, "house_percentage" => "30")["allocation"]).to eq([])
    end
  end

  describe ".same_amount" do
    it "pays everyone one flat amount — no cut off the top, no per-person exceptions — and leaves the base alone" do
      base = { "allocation" => [ { "type" => "percentage", "value" => 50.0 }, { "type" => "remainder" } ],
               "distribution" => { "method" => "shares", "default_shares" => 1.0 },
               "performer_overrides" => { "7" => { "flat_amount" => 100.0 } } }

      rules = described_class.same_amount(base, "60")

      expect(rules).to eq("allocation" => [], "distribution" => { "method" => "flat_fee", "flat_amount" => 60.0 }, "performer_overrides" => {})
      expect(base["allocation"].size).to eq(2)
    end
  end
end
