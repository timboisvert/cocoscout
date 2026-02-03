# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowFinancials do
  describe "associations" do
    it "responds to show" do
      expect(described_class.new).to respond_to(:show)
    end

    it "responds to expense_items" do
      expect(described_class.new).to respond_to(:expense_items)
    end
  end

  describe "validations" do
    it "requires unique show_id" do
      financials1 = create(:show_financials)
      financials2 = build(:show_financials, show: financials1.show)
      expect(financials2).not_to be_valid
      expect(financials2.errors[:show_id]).to be_present
    end
  end

  describe "revenue type methods" do
    describe "#ticket_sales?" do
      it "returns true when revenue_type is nil" do
        financials = build(:show_financials, revenue_type: nil)
        expect(financials.ticket_sales?).to be true
      end

      it "returns true when revenue_type is ticket_sales" do
        financials = build(:show_financials, revenue_type: "ticket_sales")
        expect(financials.ticket_sales?).to be true
      end

      it "returns false when revenue_type is flat_fee" do
        financials = build(:show_financials, revenue_type: "flat_fee")
        expect(financials.ticket_sales?).to be false
      end
    end

    describe "#flat_fee?" do
      it "returns true when revenue_type is flat_fee" do
        financials = build(:show_financials, revenue_type: "flat_fee")
        expect(financials.flat_fee?).to be true
      end

      it "returns false when revenue_type is ticket_sales" do
        financials = build(:show_financials, revenue_type: "ticket_sales")
        expect(financials.flat_fee?).to be false
      end
    end
  end

  describe "#primary_revenue" do
    it "returns ticket_revenue for ticket_sales type" do
      financials = build(:show_financials, revenue_type: "ticket_sales", ticket_revenue: 1500.0)
      expect(financials.primary_revenue).to eq(1500.0)
    end

    it "returns flat_fee for flat_fee type" do
      financials = build(:show_financials, :flat_fee, flat_fee: 2000.0)
      expect(financials.primary_revenue).to eq(2000.0)
    end

    it "returns 0 when nil" do
      financials = build(:show_financials, revenue_type: "ticket_sales", ticket_revenue: nil)
      expect(financials.primary_revenue).to eq(0)
    end
  end

  describe "#calculated_other_revenue" do
    it "returns stored amount when no details" do
      financials = build(:show_financials, other_revenue: 250.0, other_revenue_details: nil)
      expect(financials.calculated_other_revenue).to eq(250.0)
    end

    it "calculates from details array" do
      financials = build(:show_financials,
                         other_revenue_details: [
                           { "amount" => 100.0 },
                           { "amount" => 150.0 }
                         ])
      expect(financials.calculated_other_revenue).to eq(250.0)
    end
  end

  describe "#calculated_expenses" do
    it "returns stored expenses when no details" do
      financials = build(:show_financials, expenses: 200.0, expense_details: nil)
      expect(financials.calculated_expenses).to eq(200.0)
    end

    it "calculates from expense_details" do
      financials = build(:show_financials, :with_expense_details)
      expect(financials.calculated_expenses).to eq(150.0)
    end
  end

  describe "#total_revenue" do
    it "sums primary and other revenue" do
      financials = build(:show_financials,
                         ticket_revenue: 1500.0,
                         other_revenue: 250.0)
      expect(financials.total_revenue).to eq(1750.0)
    end
  end

  describe "#net_revenue" do
    it "subtracts expenses from total revenue" do
      financials = create(:show_financials,
                          ticket_revenue: 1500.0,
                          other_revenue: 250.0,
                          expenses: 200.0)
      expect(financials.net_revenue).to eq(1550.0)
    end
  end

  describe "#complete?" do
    it "returns true when data_confirmed flag is set" do
      financials = build(:show_financials, :complete)
      expect(financials.complete?).to be true
    end

    it "returns false when not data_confirmed and no revenue data" do
      financials = build(:show_financials, data_confirmed: false, ticket_revenue: nil, flat_fee: nil)
      expect(financials.complete?).to be false
    end
  end

  describe "#has_data?" do
    it "returns true when ticket revenue present" do
      financials = build(:show_financials, ticket_revenue: 100.0)
      expect(financials.has_data?).to be true
    end

    it "returns true when flat fee present" do
      financials = build(:show_financials, :flat_fee)
      expect(financials.has_data?).to be true
    end

    it "returns false when no revenue data" do
      financials = build(:show_financials, ticket_revenue: nil, ticket_count: nil, flat_fee: nil, other_revenue: nil, expenses: nil, data_confirmed: false)
      expect(financials.has_data?).to be false
    end
  end
end
