# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowPayout do
  describe "associations" do
    it "responds to show" do
      expect(described_class.new).to respond_to(:show)
    end

    it "responds to payout_scheme" do
      expect(described_class.new).to respond_to(:payout_scheme)
    end

    it "responds to line_items" do
      expect(described_class.new).to respond_to(:line_items)
    end
  end

  describe "validations" do
    it "requires unique show_id" do
      payout1 = create(:show_payout)
      payout2 = build(:show_payout, show: payout1.show)
      expect(payout2).not_to be_valid
      expect(payout2.errors[:show_id]).to be_present
    end
  end

  describe "scopes" do
    let!(:awaiting) { create(:show_payout, status: "awaiting_payout") }
    let!(:paid) { create(:show_payout, :paid) }

    describe ".awaiting_payout" do
      it "returns awaiting payouts" do
        expect(ShowPayout.awaiting_payout).to include(awaiting)
        expect(ShowPayout.awaiting_payout).not_to include(paid)
      end
    end

    describe ".paid" do
      it "returns paid payouts" do
        expect(ShowPayout.paid).to include(paid)
        expect(ShowPayout.paid).not_to include(awaiting)
      end
    end

    describe ".not_paid" do
      it "returns non-paid payouts" do
        expect(ShowPayout.not_paid).to include(awaiting)
        expect(ShowPayout.not_paid).not_to include(paid)
      end
    end
  end

  describe "#effective_rules" do
    it "returns override rules when present" do
      payout = build(:show_payout, :with_overrides)
      expect(payout.effective_rules).to eq({ "distribution" => { "method" => "equal" } })
    end

    it "falls back to payout scheme rules" do
      scheme = create(:payout_scheme, rules: { "distribution" => { "method" => "per_ticket" } })
      payout = build(:show_payout, payout_scheme: scheme, override_rules: nil)
      expect(payout.effective_rules["distribution"]["method"]).to eq("per_ticket")
    end

    it "returns empty hash when no rules" do
      payout = build(:show_payout, payout_scheme: nil, override_rules: nil)
      expect(payout.effective_rules).to eq({})
    end
  end

  describe "#has_overrides?" do
    it "returns true when override_rules present" do
      payout = build(:show_payout, :with_overrides)
      expect(payout.has_overrides?).to be true
    end

    it "returns false when no overrides" do
      payout = build(:show_payout, override_rules: nil)
      expect(payout.has_overrides?).to be false
    end
  end

  describe "#customization_summary" do
    let(:organization) { create(:organization) }
    let(:production) { create(:production, organization: organization) }
    let(:show) { create(:show, production: production) }
    let(:scheme) do
      PayoutScheme.create!(
        organization: organization, name: "House Split",
        rules: {
          "allocation" => [ { "type" => "percentage", "value" => 40.0, "label" => "House take" }, { "type" => "remainder" } ],
          "distribution" => { "method" => "shares", "default_shares" => 1.0 },
          "performer_overrides" => {}
        }
      )
    end
    let(:payout) { create(:show_payout, show: show, payout_scheme: scheme) }

    it "is nil without a customization" do
      expect(payout.customization_summary).to be_nil
    end

    it "spells out a changed house take and expenses-first" do
      payout.update!(override_rules: scheme.rules.deep_merge("allocation" => [ { "type" => "expenses_first" }, { "type" => "percentage", "value" => 30.0 }, { "type" => "remainder" } ]))
      expect(payout.customization_summary).to eq("House 30% instead of 40%; Expenses covered first")
    end

    it "spells out changed shares" do
      payout.update!(override_rules: scheme.rules.deep_merge("distribution" => { "default_shares" => 2.0 }))
      expect(payout.customization_summary).to eq("2 shares each instead of 1")
    end

    it "says everyone is paid the same amount when one flat amount replaces the calculation" do
      payout.update!(override_rules: PayoutRulesBuilder.same_amount(scheme.rules, 60))
      expect(payout.customization_summary).to eq("Everyone $60")
    end

    it "says the same for a flat amount laid over a flat calculation" do
      scheme.update!(rules: { "allocation" => [], "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 } })
      payout.update!(override_rules: { "allocation" => [], "distribution" => { "method" => "flat_fee", "flat_amount" => 60.0 } })
      expect(payout.customization_summary).to eq("Everyone $60")
    end

    it "spells out per-ticket rate and minimum changes" do
      scheme.update!(rules: { "distribution" => { "method" => "per_ticket_guaranteed", "per_ticket_rate" => 1.0, "minimum" => 25.0 } })
      payout.update!(override_rules: { "distribution" => { "method" => "per_ticket_guaranteed", "per_ticket_rate" => 1.5, "minimum" => 30.0 } })
      expect(payout.customization_summary).to eq("$1.50/ticket instead of $1; Minimum $30 instead of $25")
    end

    it "spells out a changed act schedule" do
      scheme.update!(rules: { "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 25.0 } })
      payout.update!(override_rules: { "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 30.0 } })
      expect(payout.customization_summary).to eq("$30.00 per act instead of $25.00 per act")
    end

    it "names the people given exact amounts, guests included" do
      jane = create(:person, name: "Jane Doe")
      role = create(:role, production: production)
      gigi = create(:show_person_role_assignment, show: show, role: role, guest_name: "Gigi", assignable: nil)
      payout.update!(override_rules: scheme.rules.merge("performer_overrides" => { jane.id.to_s => { "flat_amount" => 100.0 }, "guest_#{gigi.id}" => { "flat_amount" => 40.0 } }))
      expect(payout.customization_summary).to eq("Jane Doe $100, Gigi (guest) $40")
    end

    it "says when the approach itself was swapped (legacy overrides)" do
      payout.update!(override_rules: { "allocation" => [], "distribution" => { "method" => "per_ticket", "per_ticket_rate" => 2.0 } })
      expect(payout.customization_summary).to eq("Per ticket instead of split by shares")
    end

    it "names each person paid their own amount, and only them" do
      jane = create(:person, name: "Jane Doe")
      jack = create(:person, name: "Jack Sprat")
      payout.update!(override_rules: PayoutRulesBuilder.override(scheme.rules, performer_overrides: { jane.id.to_s => { flat_amount: "100" }, jack.id.to_s => { flat_amount: "40" } }))
      expect(payout.customization_summary).to eq("Jane Doe $100, Jack Sprat $40")
    end

    it "labels a show closed as non-paying" do
      payout.update!(override_rules: { "distribution" => { "method" => "no_pay" }, "closed_as_non_paying" => true })
      expect(payout.customization_summary).to eq("Closed as non-paying")
    end

    it "falls back to a generic line when nothing it can name differs" do
      payout.update!(override_rules: scheme.rules)
      expect(payout.customization_summary).to eq("Custom amounts")
    end
  end

  describe "what each payee stands to be paid" do
    let(:organization) { create(:organization) }
    let(:production) { create(:production, organization: organization) }
    let(:show) { create(:show, production: production) }
    let(:role) { create(:role, production: production) }
    let!(:jane) { create(:person, name: "Jane Doe") }
    let!(:jack) { create(:person, name: "Jack Sprat") }
    let!(:jane_cast) { create(:show_person_role_assignment, show: show, role: role, assignable: jane) }
    let!(:jack_cast) { create(:show_person_role_assignment, show: show, role: role, assignable: jack) }
    let!(:gigi_cast) { create(:show_person_role_assignment, show: show, role: role, guest_name: "Gigi", assignable: nil) }
    let!(:financials) { create(:show_financials, :complete, show: show, ticket_count: 100, ticket_revenue: 1000, expenses: 0) }
    let(:scheme) do
      PayoutScheme.create!(
        organization: organization, name: "House Split",
        rules: {
          "allocation" => [ { "type" => "percentage", "value" => 40.0, "label" => "House take" }, { "type" => "remainder" } ],
          "distribution" => { "method" => "shares", "default_shares" => 1.0 },
          "performer_overrides" => {}
        }
      )
    end
    let!(:payout) { create(:show_payout, show: show, payout_scheme: scheme, status: "awaiting_payout") }

    describe "#preview_amounts" do
      it "dry-runs the calculation, keyed by act key, and leaves no trace of it" do
        amounts = payout.preview_amounts

        expect(amounts).to eq("Person_#{jane.id}" => 200.0, "Person_#{jack.id}" => 200.0, "guest_#{gigi_cast.id}" => 200.0)
        expect(payout.line_items).to be_empty
        expect(payout.calculated_at).to be_nil
        expect(payout.total_payout.to_f).to eq(0.0)
        expect(ShowPayoutLineItem.where(show_payout: payout)).to be_empty
        expect(PayoutLedgerEntry.where(payee: jane)).to be_empty
        expect(show.reload.show_payout.calculated_at).to be_nil
      end

      it "runs whichever rules it's given (the customization, or the calculation underneath)" do
        payout.update!(override_rules: PayoutRulesBuilder.same_amount(scheme.rules, 60))

        expect(payout.preview_amounts.values).to all(eq(60.0))
        expect(payout.preview_amounts(payout.base_rules).values).to all(eq(200.0))
      end

      it "is empty when the calculation can't run yet" do
        financials.update!(data_confirmed: false, ticket_revenue: nil)
        show.reload
        expect(payout.preview_amounts).to eq({})
      end
    end

    describe "#current_amounts and #calculated_total" do
      it "reads the calculated line items once the payout is calculated" do
        payout.line_items.create!(payee: jane, amount: 111)
        payout.line_items.create!(payee: jack, amount: 222)
        payout.line_items.create!(is_guest: true, guest_name: "Gigi", amount: 267)
        payout.line_items.create!(payee: create(:person, name: "Producer"), amount: 50, is_individual_allocation: true)
        payout.update!(calculated_at: Time.current, total_payout: 650)

        expect(payout.current_amounts).to eq("Person_#{jane.id}" => 111.0, "Person_#{jack.id}" => 222.0, "guest_#{gigi_cast.id}" => 267.0)
        expect(payout.calculated_total).to eq(600.0)
      end

      it "measures a customization against the calculation underneath it" do
        payout.update!(override_rules: PayoutRulesBuilder.same_amount(scheme.rules, 60))

        expect(payout.current_amounts.values).to all(eq(60.0))
        expect(payout.calculated_total).to eq(600.0)
      end
    end

    describe "#fixed_pot?" do
      it "is true for equal and shares, false for a flat amount" do
        expect(payout.fixed_pot?).to be(true)
        scheme.update!(rules: { "allocation" => [], "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 } })
        expect(payout.reload.fixed_pot?).to be(false)
      end
    end
  end

  describe "status methods" do
    describe "#awaiting_payout?" do
      it "returns true when status is awaiting_payout" do
        payout = build(:show_payout, status: "awaiting_payout")
        expect(payout.awaiting_payout?).to be true
      end
    end

    describe "#paid?" do
      it "returns true when status is paid" do
        payout = build(:show_payout, :paid)
        expect(payout.paid?).to be true
      end
    end
  end

  describe "#recalculate_total!" do
    it "sums line item amounts" do
      payout = create(:show_payout)
      person1 = create(:person)
      person2 = create(:person)
      create(:show_payout_line_item, show_payout: payout, payee: person1, amount: 100)
      create(:show_payout_line_item, show_payout: payout, payee: person2, amount: 50)

      payout.recalculate_total!
      expect(payout.total_payout).to eq(150)
    end
  end

  describe "#mark_paid!" do
    it "sets status to paid" do
      payout = create(:show_payout)
      payout.mark_paid!

      expect(payout.status).to eq("paid")
    end
  end
end
