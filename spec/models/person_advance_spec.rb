# frozen_string_literal: true

require "rails_helper"

RSpec.describe PersonAdvance do
  describe "associations" do
    it "responds to person" do
      expect(described_class.new).to respond_to(:person)
    end

    it "responds to production" do
      expect(described_class.new).to respond_to(:production)
    end

    it "responds to show" do
      expect(described_class.new).to respond_to(:show)
    end

    it "responds to issued_by" do
      expect(described_class.new).to respond_to(:issued_by)
    end

    it "responds to paid_by" do
      expect(described_class.new).to respond_to(:paid_by)
    end

    it "responds to advance_applications" do
      expect(described_class.new).to respond_to(:advance_applications)
    end
  end

  describe "validations" do
    it "requires original_amount to be present" do
      advance = build(:person_advance, original_amount: nil)
      expect(advance).not_to be_valid
      expect(advance.errors[:original_amount]).to be_present
    end

    it "requires original_amount to be greater than 0" do
      advance = build(:person_advance, original_amount: 0)
      expect(advance).not_to be_valid
      expect(advance.errors[:original_amount]).to be_present
    end

    it "requires remaining_balance to be greater than or equal to 0" do
      advance = build(:person_advance)
      advance.remaining_balance = -10
      expect(advance).not_to be_valid
      expect(advance.errors[:remaining_balance]).to be_present
    end

    it "requires issued_at to be present" do
      advance = build(:person_advance, issued_at: nil)
      expect(advance).not_to be_valid
      expect(advance.errors[:issued_at]).to be_present
    end

    it "requires status to be valid" do
      advance = build(:person_advance, status: "invalid")
      expect(advance).not_to be_valid
      expect(advance.errors[:status]).to be_present
    end

    it "requires advance_type to be valid" do
      advance = build(:person_advance, advance_type: "invalid")
      expect(advance).not_to be_valid
      expect(advance.errors[:advance_type]).to be_present
    end

    describe "show_required_for_show_type" do
      it "requires show when advance_type is show" do
        advance = build(:person_advance, advance_type: "show", show: nil)
        expect(advance).not_to be_valid
        expect(advance.errors[:show]).to be_present
      end

      it "does not require show when advance_type is general" do
        advance = build(:person_advance, advance_type: "general", show: nil)
        expect(advance).to be_valid
      end
    end

    describe "show_belongs_to_production" do
      it "validates show belongs to the same production" do
        production = create(:production)
        other_production = create(:production)
        show = create(:show, production: other_production)

        advance = build(:person_advance, production: production, show: show, advance_type: "show")
        expect(advance).not_to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:pending_adv) { create(:person_advance, status: "pending") }
    let!(:partial) { create(:person_advance, :partial) }
    let!(:settled) { create(:person_advance, :settled) }
    let!(:written_off) { create(:person_advance, :written_off) }
    let!(:paid) { create(:person_advance, :paid) }
    let!(:unpaid) { create(:person_advance, paid_at: nil) }

    describe ".pending" do
      it "returns pending advances" do
        expect(PersonAdvance.pending).to include(pending_adv)
      end
    end

    describe ".partial" do
      it "returns partial advances" do
        expect(PersonAdvance.partial).to include(partial)
      end
    end

    describe ".not_settled" do
      it "returns pending and partial advances" do
        expect(PersonAdvance.not_settled).to include(pending_adv, partial)
        expect(PersonAdvance.not_settled).not_to include(settled, written_off)
      end
    end

    describe ".settled" do
      it "returns settled advances" do
        expect(PersonAdvance.settled).to include(settled)
      end
    end

    describe ".paid" do
      it "returns paid advances" do
        expect(PersonAdvance.paid).to include(paid)
        expect(PersonAdvance.paid).not_to include(unpaid)
      end
    end

    describe ".unpaid" do
      it "returns unpaid advances" do
        expect(PersonAdvance.unpaid).to include(unpaid)
        expect(PersonAdvance.unpaid).not_to include(paid)
      end
    end
  end

  describe "#paid?" do
    it "returns true when paid_at is set" do
      advance = build(:person_advance, :paid)
      expect(advance.paid?).to be true
    end

    it "returns false when paid_at is nil" do
      advance = build(:person_advance, paid_at: nil)
      expect(advance.paid?).to be false
    end
  end

  describe "#settled?" do
    it "returns true when status is settled" do
      advance = build(:person_advance, :settled)
      expect(advance.settled?).to be true
    end
  end

  describe "#applied_amount" do
    it "calculates applied amount from original minus remaining" do
      advance = build(:person_advance, original_amount: 100.0, remaining_balance: 40.0)
      expect(advance.applied_amount).to eq(60.0)
    end
  end

  describe "#mark_paid!" do
    it "sets paid_at and paid_by" do
      payer = create(:user)
      advance = create(:person_advance)

      advance.mark_paid!(payer, method: "venmo")

      expect(advance.paid_at).to be_present
      expect(advance.paid_by).to eq(payer)
      expect(advance.payment_method).to eq("venmo")
    end
  end

  describe "#apply!" do
    let(:production) { create(:production) }
    let(:show) { create(:show, production: production) }
    let(:show_payout) { create(:show_payout, show: show) }
    let(:person) { create(:person) }
    let(:advance) { create(:person_advance, original_amount: 100.0, remaining_balance: 100.0) }
    let(:line_item) { create(:show_payout_line_item, show_payout: show_payout, payee: person) }

    it "reduces remaining balance" do
      advance.apply!(30.0, line_item)
      expect(advance.remaining_balance).to eq(70.0)
    end

    it "creates advance_application record" do
      expect {
        advance.apply!(30.0, line_item)
      }.to change { AdvanceRecovery.count }.by(1)
    end

    it "updates status to partial when partially recovered" do
      advance.apply!(30.0, line_item)
      expect(advance.status).to eq("partial")
    end

    it "updates status to settled when fully recovered" do
      advance.apply!(100.0, line_item)
      expect(advance.status).to eq("settled")
    end
  end

  describe "#write_off!" do
    it "sets status to written_off" do
      advance = create(:person_advance, remaining_balance: 50.0)
      advance.write_off!(notes: "Performer left company")
      expect(advance.status).to eq("written_off")
    end
  end
end
