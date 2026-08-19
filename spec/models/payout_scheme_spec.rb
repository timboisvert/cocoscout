# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutScheme do
  let(:organization) { create(:organization, :pro) }
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

    it "with no date and history in place, takes over from today and keeps the earlier scheme for the shows before" do
      new_scheme.make_production_scheme!(production)

      defaults = PayoutSchemeDefault.for_production(production).order(:effective_from)
      expect(defaults.map(&:payout_scheme)).to eq([ old_scheme, new_scheme ])
      expect(defaults.first.effective_from).to eq(past_show.date_and_time.to_date)
      expect(defaults.last.effective_from).to eq(Date.current)

      expect(described_class.default_for_show(past_show)).to eq(old_scheme)
      expect(described_class.default_for_show(soon_show)).to eq(new_scheme)
      expect(past_payout.reload.payout_scheme).to eq(old_scheme)
      expect(soon_payout.reload.payout_scheme).to eq(new_scheme)
      expect(later_payout.reload.payout_scheme).to eq(new_scheme)
    end

    it "with no date and no history, reaches back to the production's first show and restamps every pending payout" do
      PayoutSchemeDefault.for_production(production).destroy_all

      new_scheme.make_production_scheme!(production)

      expect(PayoutSchemeDefault.for_production(production).pluck(:payout_scheme_id)).to eq([ new_scheme.id ])
      expect(PayoutSchemeDefault.for_production(production).first.effective_from).to eq(past_show.date_and_time.to_date)
      expect([ past_payout, soon_payout, later_payout ].map { |p| p.reload.payout_scheme }).to all(eq(new_scheme))
    end

    it "with no date, drops switches scheduled for later (any scheme) and its own rows, but not other schemes' history" do
      third = described_class.create!(organization: organization, name: "Third", rules: flat_rules)
      third.make_production_scheme!(production, starting_on: 2.weeks.from_now.to_date)
      new_scheme.make_production_scheme!(production, starting_on: 4.weeks.from_now.to_date)

      new_scheme.make_production_scheme!(production)

      defaults = PayoutSchemeDefault.for_production(production).order(:effective_from)
      expect(defaults.map(&:payout_scheme)).to eq([ old_scheme, new_scheme ])
      expect(defaults.last.effective_from).to eq(Date.current)
      expect(described_class.current_default_for_production(production, on: 5.weeks.from_now.to_date)).to eq(new_scheme)
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

  describe "#stop_covering!" do
    let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }
    let!(:pending) { create(:show_payout, show: show, payout_scheme: nil, calculated_at: nil) }

    it "removes only this scheme's rows and leaves the production on what remains" do
      create(:show, production: production, date_and_time: 3.weeks.ago)
      old_scheme.make_production_scheme!(production) # reaches back three weeks
      new_scheme.make_production_scheme!(production) # from today
      pending.update!(payout_scheme: new_scheme)

      new_scheme.stop_covering!(production)

      expect(PayoutSchemeDefault.for_production(production).map(&:payout_scheme)).to eq([ old_scheme ])
      expect(described_class.current_default_for_production(production)).to eq(old_scheme)
      expect(pending.reload.payout_scheme).to eq(old_scheme)
    end

    it "leaves the production with nothing, and its pending payouts unstamped, when it was the only one" do
      new_scheme.make_production_scheme!(production)
      expect(pending.reload.payout_scheme).to eq(new_scheme)

      new_scheme.stop_covering!(production)

      expect(PayoutSchemeDefault.for_production(production)).to be_empty
      expect(described_class.current_default_for_production(production)).to be_nil
      expect(pending.reload.payout_scheme).to be_nil
    end

    it "does not touch the scheme's rows on other productions" do
      other = create(:production, organization: organization)
      new_scheme.make_production_scheme!(production)
      new_scheme.make_production_scheme!(other)

      new_scheme.stop_covering!(production)

      expect(described_class.current_default_for_production(other)).to eq(new_scheme)
    end
  end

  describe "when the production doesn't pay performers" do
    let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }

    before do
      new_scheme.make_production_scheme!(production)
      production.update!(pays_performers: false)
    end

    it "resolves to no calculation even though the rows are kept" do
      expect(PayoutSchemeDefault.for_production(production).count).to eq(1)
      expect(described_class.default_for_show(show)).to be_nil
      expect(described_class.current_default_for_production(production)).to be_nil
      expect(described_class.current_defaults_for_productions([ production ])).to eq({ production.id => nil })
    end

    it "still shows the kept calculation when asked to include paused pay" do
      expect(described_class.current_default_for_production(production, include_paused: true)).to eq(new_scheme)
    end

    it "resolves again once pay is back on" do
      production.update!(pays_performers: true)
      expect(described_class.default_for_show(show)).to eq(new_scheme)
      expect(described_class.current_default_for_production(production)).to eq(new_scheme)
    end
  end

  describe ".current_defaults_for_productions" do
    it "answers for every production in one query, picking the row in effect today" do
      other = create(:production, organization: organization)
      bare = create(:production, organization: organization)
      old_scheme.make_production_scheme!(production)
      new_scheme.make_production_scheme!(production, starting_on: 2.weeks.from_now.to_date)
      new_scheme.make_production_scheme!(other)

      result = nil
      # The rows, then their schemes — not one lookup per production.
      expect(count_queries { result = described_class.current_defaults_for_productions([ production, other, bare ]) }).to eq(2)
      expect(result).to eq({ production.id => old_scheme, other.id => new_scheme, bare.id => nil })
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

  describe "show roles priced by name" do
    let(:distribution) do
      { "method" => "per_act", "act_mode" => "tiers", "tiers" => [ { "acts" => 1, "amount" => 75.0 } ],
        "role_amounts" => [ { "name" => "MC", "amount" => 100 }, { "name" => "Stage Kitten", "amount" => 35 } ] }
    end

    it "prices a role by name, whatever the case or spacing" do
      expect(described_class.role_amount_for(distribution, "mc")).to eq(100.0)
      expect(described_class.role_amount_for(distribution, "  stage  kitten ")).to eq(35.0)
      expect(described_class.role_amount_for(distribution, "Host")).to be_nil
    end

    it "tells an unpriced role from one priced at zero" do
      free = distribution.merge("role_amounts" => [ { "name" => "Usher", "amount" => 0 } ])
      expect(described_class.role_amount_for(free, "Usher")).to eq(0.0)
      expect(described_class.role_amount_for(free, "MC")).to be_nil
    end

    it "defaults stacking to both and only accepts the known choices" do
      expect(described_class.role_stacking(distribution)).to eq("both")
      expect(described_class.role_stacking(distribution.merge("role_stacking" => "higher"))).to eq("higher")
      expect(described_class.role_stacking(distribution.merge("role_stacking" => "sometimes"))).to eq("both")
    end

    it "spells the roles and the stacking out" do
      expect(described_class.role_rules_description(distribution)).to eq("MC $100.00, Stage Kitten $35.00 — added to act pay")
      expect(described_class.role_rules_description(distribution.merge("role_stacking" => "role_only"))).to eq("MC $100.00, Stage Kitten $35.00 — instead of act pay")
      expect(described_class.role_rules_description(distribution.merge("role_stacking" => "higher"))).to eq("MC $100.00, Stage Kitten $35.00 — or act pay, whichever is higher")
      expect(described_class.role_rules_description({})).to eq("No show roles priced")
    end

    it "pays a role holder who also performs one set amount, or reads their own table" do
      flat = distribution.merge("role_stacking" => "flat", "role_with_acts_amount" => 150)
      expect(described_class.role_with_acts_amount_for(flat, 1)).to eq(150.0)
      expect(described_class.role_with_acts_amount_for(flat, 3)).to eq(150.0)
      expect(described_class.role_rules_description(flat)).to eq("MC $100.00, Stage Kitten $35.00 — $150.00 all in when they also perform")

      table = distribution.merge("role_stacking" => "table",
                                 "role_with_acts_tiers" => [ { "acts" => 2, "amount" => 160 }, { "acts" => 1, "amount" => 120 } ],
                                 "role_with_acts_additional_rate" => 30)
      expect(described_class.role_with_acts_amount_for(table, 1)).to eq(120.0)
      expect(described_class.role_with_acts_amount_for(table, 2)).to eq(160.0)
      expect(described_class.role_with_acts_amount_for(table, 4)).to eq(220.0)
      expect(described_class.role_rules_description(table))
        .to eq("MC $100.00, Stage Kitten $35.00 — their own act table when they also perform (1 act $120.00, 2 acts $160.00, then $30.00 an act)")

      # The other stackings combine role and act pay in the calculator instead
      expect(described_class.role_with_acts_amount_for(distribution, 1)).to be_nil
    end

    it "shows up in the rules summary only when there are any" do
      priced = create(:payout_scheme, organization: create(:organization), rules: { "allocation" => [], "distribution" => distribution })
      expect(priced.rules_summary).to include("Show roles: MC $100.00, Stage Kitten $35.00 — added to act pay")

      plain = create(:payout_scheme, organization: create(:organization), rules: { "allocation" => [], "distribution" => distribution.except("role_amounts") })
      expect(plain.rules_summary).not_to include("Show roles")
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
