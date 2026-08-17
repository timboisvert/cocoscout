# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutScheme do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:flat_rules) { { "allocation" => [], "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 }, "performer_overrides" => {} } }
  let(:old_scheme) { described_class.create!(organization: organization, name: "Old", rules: flat_rules) }
  let(:new_scheme) { described_class.create!(organization: organization, name: "New", rules: flat_rules) }

  describe "#make_production_scheme!" do
    let!(:past_show) { create(:show, production: production, date_and_time: 3.weeks.ago) }
    let!(:soon_show) { create(:show, production: production, date_and_time: 1.week.from_now) }
    let!(:later_show) { create(:show, production: production, date_and_time: 5.weeks.from_now) }
    let!(:past_payout) { create(:show_payout, show: past_show, payout_scheme: old_scheme, calculated_at: nil) }
    let!(:soon_payout) { create(:show_payout, show: soon_show, payout_scheme: old_scheme, calculated_at: nil) }
    let!(:later_payout) { create(:show_payout, show: later_show, payout_scheme: old_scheme, calculated_at: nil) }

    before { old_scheme.make_production_scheme!(production) }

    it "with no date, replaces the production's scheme back to its first show and restamps every pending payout" do
      new_scheme.make_production_scheme!(production)

      expect(PayoutSchemeDefault.for_production(production).pluck(:payout_scheme_id)).to eq([ new_scheme.id ])
      expect(PayoutSchemeDefault.for_production(production).first.effective_from).to eq(past_show.date_and_time.to_date)
      expect([ past_payout, soon_payout, later_payout ].map { |p| p.reload.payout_scheme }).to all(eq(new_scheme))
    end

    it "with a date, leaves earlier shows on the old scheme and switches from that date on" do
      switch = 3.weeks.from_now.to_date
      new_scheme.make_production_scheme!(production, starting_on: switch)

      defaults = PayoutSchemeDefault.for_production(production).order(:effective_from)
      expect(defaults.map(&:payout_scheme)).to eq([ old_scheme, new_scheme ])
      expect(defaults.last.effective_from).to eq(switch)

      expect(described_class.default_for_show(soon_show)).to eq(old_scheme)
      expect(described_class.default_for_show(later_show)).to eq(new_scheme)
      expect(described_class.current_default_for_production(production)).to eq(old_scheme)
      expect(described_class.current_default_for_production(production, on: switch)).to eq(new_scheme)

      expect(past_payout.reload.payout_scheme).to eq(old_scheme)
      expect(soon_payout.reload.payout_scheme).to eq(old_scheme)
      expect(later_payout.reload.payout_scheme).to eq(new_scheme)
    end

    it "with a date, replaces only the production's defaults dated on or after it" do
      switch = 3.weeks.from_now.to_date
      third = described_class.create!(organization: organization, name: "Third", rules: flat_rules)
      third.make_production_scheme!(production, starting_on: switch + 7)

      new_scheme.make_production_scheme!(production, starting_on: switch)

      expect(PayoutSchemeDefault.for_production(production).map(&:payout_scheme)).to contain_exactly(old_scheme, new_scheme)
    end

    it "with a date, doesn't touch payouts that were already calculated" do
      later_payout.update!(calculated_at: Time.current)

      new_scheme.make_production_scheme!(production, starting_on: 3.weeks.from_now.to_date)

      expect(later_payout.reload.payout_scheme).to eq(old_scheme)
    end
  end

  describe ".act_amount with a tiers table" do
    let(:tiers) { { "act_mode" => "tiers", "tiers" => [ { "acts" => 1, "amount" => 75.0 }, { "acts" => 2, "amount" => 125.0 } ] } }

    it "pays the last row for anything past the table when there's no beyond rate" do
      expect(described_class.act_amount(tiers, 4)).to eq(125.0)
    end

    it "adds the beyond rate for every act past the last row" do
      beyond = tiers.merge("additional_act_rate" => 50.0)
      expect(described_class.act_amount(beyond, 2)).to eq(125.0)
      expect(described_class.act_amount(beyond, 3)).to eq(175.0)
      expect(described_class.act_amount(beyond, 4)).to eq(225.0)
    end

    it "spells the beyond rate out" do
      expect(described_class.act_rules_description(tiers.merge("additional_act_rate" => 50.0)))
        .to eq("1 act $75.00, 2 acts $125.00, then $50.00 per act")
      expect(described_class.act_rules_description(tiers)).to eq("1 act $75.00, 2+ acts $125.00")
    end
  end

  describe ".suggested_name" do
    def rules_for(distribution, allocation = [])
      { "allocation" => allocation, "distribution" => distribution }
    end

    it "reads a name off each kind of calculation" do
      expect(described_class.suggested_name(rules_for({ "method" => "flat_fee", "flat_amount" => 50.0 }))).to eq("$50 flat per performer")
      expect(described_class.suggested_name(rules_for({ "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 25.0 }))).to eq("$25 per act")
      expect(described_class.suggested_name(rules_for({ "method" => "per_act", "act_mode" => "tiers",
                                                  "tiers" => [ { "acts" => 1, "amount" => 75.0 }, { "acts" => 2, "amount" => 125.0 } ],
                                                  "additional_act_rate" => 50.0 })))
        .to eq("1 act $75, 2 acts $125, then $50 each")
      expect(described_class.suggested_name(rules_for({ "method" => "per_ticket", "per_ticket_rate" => 2.0 }))).to eq("$2/ticket")
      expect(described_class.suggested_name(rules_for({ "method" => "per_ticket_guaranteed", "per_ticket_rate" => 2.5, "minimum" => 30.0 }))).to eq("$2.50/ticket, min $30")
      expect(described_class.suggested_name(rules_for({ "method" => "equal" }, [ { "type" => "percentage", "value" => 40.0 }, { "type" => "remainder" } ])))
        .to eq("Even split after 40% house")
      expect(described_class.suggested_name(rules_for({ "method" => "equal" }))).to eq("Even split")
      expect(described_class.suggested_name(rules_for({ "method" => "shares", "default_shares" => 1.0 }))).to eq("Split by shares")
    end
  end
end
