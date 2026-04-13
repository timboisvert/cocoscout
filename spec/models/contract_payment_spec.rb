# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractPayment, type: :model do
  describe "associations" do
    it "belongs to contract" do
      payment = create(:contract_payment)
      expect(payment.contract).to be_present
    end
  end

  describe "validations" do
    it "requires amount" do
      payment = build(:contract_payment, amount: nil)
      expect(payment).not_to be_valid
    end

    it "requires amount >= 0" do
      payment = build(:contract_payment, amount: -10)
      expect(payment).not_to be_valid
    end

    it "requires amount > 0 when not TBD" do
      payment = build(:contract_payment, amount: 0, amount_tbd: false)
      expect(payment).not_to be_valid
    end

    it "allows amount of 0 when TBD" do
      payment = build(:contract_payment, amount: 0, amount_tbd: true)
      expect(payment).to be_valid
    end

    it "requires due_date" do
      payment = build(:contract_payment, due_date: nil)
      expect(payment).not_to be_valid
    end

    it "requires direction" do
      payment = build(:contract_payment, direction: nil)
      expect(payment).not_to be_valid
    end
  end

  describe "enums" do
    describe "direction" do
      it "supports incoming" do
        payment = build(:contract_payment, direction: "incoming")
        expect(payment.direction_incoming?).to be true
      end

      it "supports outgoing" do
        payment = build(:contract_payment, direction: "outgoing")
        expect(payment.direction_outgoing?).to be true
      end
    end

    describe "status" do
      it "supports pending" do
        payment = build(:contract_payment, status: "pending")
        expect(payment.status_pending?).to be true
      end

      it "supports paid" do
        payment = build(:contract_payment, :paid)
        expect(payment.status_paid?).to be true
      end

      it "supports cancelled" do
        payment = build(:contract_payment, status: "cancelled")
        expect(payment.status_cancelled?).to be true
      end
    end
  end

  describe "scopes" do
    let(:contract) { create(:contract, :active) }
    let!(:upcoming_payment) { create(:contract_payment, contract: contract, due_date: 1.week.from_now, status: "pending") }
    let!(:overdue_payment) { create(:contract_payment, contract: contract, due_date: 1.week.ago, status: "pending") }
    let!(:paid_payment) { create(:contract_payment, :paid, contract: contract, due_date: 2.weeks.ago) }

    describe ".upcoming" do
      it "returns pending payments with future due dates" do
        expect(ContractPayment.upcoming).to include(upcoming_payment)
        expect(ContractPayment.upcoming).not_to include(overdue_payment)
        expect(ContractPayment.upcoming).not_to include(paid_payment)
      end
    end

    describe ".overdue" do
      it "returns pending payments with past due dates" do
        expect(ContractPayment.overdue).to include(overdue_payment)
        expect(ContractPayment.overdue).not_to include(upcoming_payment)
        expect(ContractPayment.overdue).not_to include(paid_payment)
      end
    end
  end

  describe "#amount_tbd?" do
    it "returns true when amount_tbd is set" do
      payment = build(:contract_payment, :revenue_share_tbd)
      expect(payment.amount_tbd?).to be true
    end

    it "returns false by default" do
      payment = build(:contract_payment)
      expect(payment.amount_tbd?).to be false
    end
  end

  describe "#revenue_share?" do
    it "returns true when description contains 'Revenue Share'" do
      payment = build(:contract_payment, description: "Revenue Share Settlement")
      expect(payment.revenue_share?).to be true
    end

    it "returns true case-insensitively" do
      payment = build(:contract_payment, description: "revenue share for March")
      expect(payment.revenue_share?).to be true
    end

    it "returns false for other descriptions" do
      payment = build(:contract_payment, description: "Rental fee")
      expect(payment.revenue_share?).to be false
    end

    it "returns falsey for nil description" do
      payment = build(:contract_payment, description: nil)
      expect(payment.revenue_share?).to be_falsey
    end
  end

  describe "#overdue?" do
    it "returns true for pending payments past due date" do
      payment = build(:contract_payment, status: "pending", due_date: 1.week.ago)
      expect(payment.overdue?).to be true
    end

    it "returns false for pending payments with future due date" do
      payment = build(:contract_payment, status: "pending", due_date: 1.week.from_now)
      expect(payment.overdue?).to be false
    end

    it "returns false for paid payments past due date" do
      payment = build(:contract_payment, :paid, due_date: 1.week.ago)
      expect(payment.overdue?).to be false
    end
  end

  describe "#mark_paid!" do
    let(:payment) { create(:contract_payment, status: "pending") }

    it "changes status to paid" do
      payment.mark_paid!
      expect(payment.reload.status).to eq("paid")
    end

    it "sets paid_date" do
      payment.mark_paid!(paid_on: Date.new(2026, 3, 15))
      expect(payment.paid_date).to eq(Date.new(2026, 3, 15))
    end

    it "defaults paid_date to today" do
      payment.mark_paid!
      expect(payment.paid_date).to eq(Date.current)
    end

    it "stores payment method" do
      payment.mark_paid!(method: "bank_transfer")
      expect(payment.payment_method).to eq("bank_transfer")
    end

    it "stores reference number" do
      payment.mark_paid!(reference: "CHK-1234")
      expect(payment.reference_number).to eq("CHK-1234")
    end
  end

  describe "#formatted_amount" do
    it "formats incoming as positive" do
      payment = build(:contract_payment, direction: "incoming", amount: 500.0)
      expect(payment.formatted_amount).to eq("+$500.00")
    end

    it "formats outgoing as negative" do
      payment = build(:contract_payment, :outgoing, amount: 200.0)
      expect(payment.formatted_amount).to eq("-$200.00")
    end
  end

  describe "#status_badge_class" do
    it "returns success for paid" do
      payment = build(:contract_payment, :paid)
      expect(payment.status_badge_class).to eq("badge-success")
    end

    it "returns warning for pending not overdue" do
      payment = build(:contract_payment, status: "pending", due_date: 1.week.from_now)
      expect(payment.status_badge_class).to eq("badge-warning")
    end

    it "returns danger for pending overdue" do
      payment = build(:contract_payment, status: "pending", due_date: 1.week.ago)
      expect(payment.status_badge_class).to eq("badge-danger")
    end

    it "returns secondary for cancelled" do
      payment = build(:contract_payment, status: "cancelled")
      expect(payment.status_badge_class).to eq("badge-secondary")
    end
  end
end
