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
