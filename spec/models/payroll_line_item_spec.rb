# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayrollLineItem, type: :model do
  describe "constants" do
    it "defines PAYMENT_METHODS" do
      expect(described_class::PAYMENT_METHODS).to eq(%w[venmo cash zelle check other n/a])
    end

    it "defines PAYOUT_STATUSES" do
      expect(described_class::PAYOUT_STATUSES).to eq(%w[pending success failed])
    end
  end

  describe "associations" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:person) { create(:person) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }
    let(:pli) { create(:payroll_line_item, payroll_run: run, person: person) }

    it "belongs to payroll_run" do
      expect(pli).to respond_to(:payroll_run)
      expect(pli.payroll_run).to be_present
    end

    it "belongs to person" do
      expect(pli).to respond_to(:person)
      expect(pli.person).to be_present
    end

    it "belongs to manually_paid_by (optional)" do
      expect(pli).to respond_to(:manually_paid_by)
    end

    it "has many show_payout_line_items" do
      expect(pli).to respond_to(:show_payout_line_items)
    end

    it "has one organization through payroll_run" do
      expect(pli).to respond_to(:organization)
    end
  end

  describe "validations" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:person) { create(:person) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }

    it "validates uniqueness of person within payroll run" do
      create(:payroll_line_item, payroll_run: run, person: person)
      duplicate = build(:payroll_line_item, payroll_run: run, person: person)
      expect(duplicate).not_to be_valid
    end

    it "validates payment_method is in PAYMENT_METHODS" do
      item = build(:payroll_line_item, payroll_run: run, person: person, payment_method: "invalid")
      expect(item).not_to be_valid
    end

    it "allows nil payment_method" do
      item = build(:payroll_line_item, payroll_run: run, person: person, payment_method: nil)
      expect(item).to be_valid
    end

    it "validates payout_status is in PAYOUT_STATUSES" do
      item = build(:payroll_line_item, payroll_run: run, person: person, payout_status: "invalid")
      expect(item).not_to be_valid
    end

    it "allows nil payout_status" do
      item = build(:payroll_line_item, payroll_run: run, person: person, payout_status: nil)
      expect(item).to be_valid
    end
  end

  describe "scopes" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }
    let(:person1) { create(:person, name: "Alice") }
    let(:person2) { create(:person, name: "Bob") }

    describe ".by_name" do
      it "orders by person name" do
        item2 = create(:payroll_line_item, payroll_run: run, person: person2)
        item1 = create(:payroll_line_item, payroll_run: run, person: person1)
        expect(described_class.by_name).to eq([ item1, item2 ])
      end
    end

    describe ".paid" do
      it "returns items that are manually paid or have success status" do
        manual = create(:payroll_line_item, payroll_run: run, person: person1, manually_paid: true)
        success = create(:payroll_line_item, payroll_run: run, person: person2, payout_status: "success")
        create(:payroll_line_item, payroll_run: run, person: create(:person), manually_paid: false, payout_status: nil)

        expect(described_class.paid).to contain_exactly(manual, success)
      end
    end

    describe ".unpaid" do
      it "returns items that are not manually paid and have a non-success status" do
        create(:payroll_line_item, payroll_run: run, person: person1, manually_paid: true)
        create(:payroll_line_item, payroll_run: run, person: person2, payout_status: "success")
        # Note: payout_status must be non-nil for the scope to match (SQL NULL behavior)
        unpaid = create(:payroll_line_item, payroll_run: run, person: create(:person), manually_paid: false, payout_status: "pending")

        expect(described_class.unpaid).to contain_exactly(unpaid)
      end
    end
  end

  describe "calculated amounts" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }
    let(:person) { create(:person) }
    let(:production) { create(:production, organization: organization) }
    let(:show1) { create(:show, production: production) }
    let(:show2) { create(:show, production: production) }
    let(:show_payout1) { create(:show_payout, show: show1) }
    let(:show_payout2) { create(:show_payout, show: show2) }
    let(:pli) { create(:payroll_line_item, payroll_run: run, person: person) }

    before do
      create(:show_payout_line_item, show_payout: show_payout1, payee: person, amount: 100, advance_deduction: 20, payroll_line_item: pli)
      create(:show_payout_line_item, show_payout: show_payout2, payee: person, amount: 80, advance_deduction: 0, payroll_line_item: pli)
    end

    describe "#gross_amount" do
      it "sums amounts from linked show payout line items" do
        expect(pli.gross_amount).to eq(180)
      end
    end

    describe "#advance_deductions" do
      it "sums advance_deduction from linked show payout line items" do
        expect(pli.advance_deductions).to eq(20)
      end
    end

    describe "#net_amount" do
      it "calculates gross minus deductions" do
        expect(pli.net_amount).to eq(160)
      end
    end

    describe "#show_count" do
      it "counts linked show payout line items" do
        expect(pli.show_count).to eq(2)
      end
    end
  end

  describe "#breakdown" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }
    let(:person) { create(:person) }
    let(:production) { create(:production, organization: organization, name: "Comedy Night") }
    let(:show) { create(:show, production: production, date_and_time: Time.zone.parse("2024-06-15 20:00")) }
    let(:show_payout) { create(:show_payout, show: show) }
    let(:pli) { create(:payroll_line_item, payroll_run: run, person: person) }

    before do
      create(:show_payout_line_item, show_payout: show_payout, payee: person, amount: 100, advance_deduction: 10, payroll_line_item: pli)
    end

    it "returns show breakdown information" do
      breakdown = pli.breakdown
      expect(breakdown.length).to eq(1)
      expect(breakdown.first[:show_id]).to eq(show.id)
      expect(breakdown.first[:production_name]).to eq("Comedy Night")
      expect(breakdown.first[:amount]).to eq(100.0)
      expect(breakdown.first[:advance_deduction]).to eq(10.0)
    end
  end

  describe "#paid?" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }
    let(:person) { create(:person) }
    let(:pli) { create(:payroll_line_item, payroll_run: run, person: person) }

    it "returns true when manually paid" do
      pli.update!(manually_paid: true)
      expect(pli.paid?).to be true
    end

    it "returns true when payout_status is success" do
      pli.update!(payout_status: "success")
      expect(pli.paid?).to be true
    end

    it "returns false otherwise" do
      expect(pli.paid?).to be false
    end
  end

  describe "#mark_as_paid!" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user, status: "processing", processed_by: user) }
    let(:person) { create(:person) }
    let(:production) { create(:production, organization: organization) }
    let(:show) { create(:show, production: production) }
    let(:show_payout) { create(:show_payout, show: show) }
    let(:pli) { create(:payroll_line_item, payroll_run: run, person: person) }

    before do
      create(:show_payout_line_item, show_payout: show_payout, payee: person, amount: 100, payroll_line_item: pli)
    end

    it "marks the item as manually paid" do
      pli.mark_as_paid!(user, method: "venmo", notes: "Sent via app")

      expect(pli.manually_paid).to be true
      expect(pli.manually_paid_by).to eq(user)
      expect(pli.manually_paid_at).to be_present
      expect(pli.payment_method).to eq("venmo")
      expect(pli.payment_notes).to eq("Sent via app")
    end

    it "marks associated show payout line items as paid" do
      pli.mark_as_paid!(user)
      spli = pli.show_payout_line_items.first
      expect(spli.manually_paid).to be true
    end

    it "completes the run when all items are paid" do
      pli.mark_as_paid!(user)
      expect(run.reload.status).to eq("completed")
    end
  end

  describe "#unmark_as_paid!" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }
    let(:person) { create(:person) }
    let(:production) { create(:production, organization: organization) }
    let(:show) { create(:show, production: production) }
    let(:show_payout) { create(:show_payout, show: show) }
    let(:pli) do
      create(:payroll_line_item, payroll_run: run, person: person,
        manually_paid: true, manually_paid_by: user, manually_paid_at: Time.current,
        payment_method: "venmo", payment_notes: "Test")
    end

    before do
      create(:show_payout_line_item, show_payout: show_payout, payee: person, amount: 100, payroll_line_item: pli, manually_paid: true)
    end

    it "clears all payment fields" do
      pli.unmark_as_paid!

      expect(pli.manually_paid).to be false
      expect(pli.manually_paid_by).to be_nil
      expect(pli.manually_paid_at).to be_nil
      expect(pli.payment_method).to be_nil
      expect(pli.payment_notes).to be_nil
    end

    it "unmarks associated show payout line items" do
      pli.unmark_as_paid!
      spli = pli.show_payout_line_items.first
      expect(spli.manually_paid).to be false
    end
  end
end
