# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowFinancials, "extended tests", type: :model do
  describe "calculated_production_expenses" do
    let(:organization) { create(:organization) }
    let(:production) { create(:production, organization: organization) }
    let(:show) { create(:show, production: production, date_and_time: 1.week.ago) }
    let!(:financials) { create(:show_financials, :complete, show: show, ticket_revenue: 1000.0) }

    it "returns 0 when no production expense allocations exist" do
      expect(financials.calculated_production_expenses).to eq(0)
    end
  end

  describe "revenue calculations with edge cases" do
    it "handles zero ticket revenue" do
      financials = build(:show_financials, ticket_revenue: 0.0, other_revenue: 0.0)
      expect(financials.total_revenue).to eq(0.0)
    end

    it "handles nil values gracefully" do
      financials = build(:show_financials, ticket_revenue: nil, ticket_count: nil, other_revenue: nil)
      expect(financials.total_revenue).to eq(0.0)
    end

    it "handles flat fee with other revenue" do
      financials = build(:show_financials, :flat_fee, flat_fee: 1500.0, other_revenue: 200.0)
      expect(financials.total_revenue).to eq(1700.0)
    end

    it "handles very large amounts" do
      financials = build(:show_financials, ticket_revenue: 999_999.99, other_revenue: 50_000.01)
      expect(financials.total_revenue).to eq(1_050_000.0)
    end
  end

  describe "net_revenue edge cases" do
    it "returns negative when expenses exceed revenue" do
      financials = create(:show_financials, ticket_revenue: 100.0, expenses: 500.0)
      expect(financials.net_revenue).to be < 0
    end

    it "returns zero when revenue equals expenses" do
      financials = create(:show_financials, ticket_revenue: 500.0, expenses: 500.0, other_revenue: 0.0)
      expect(financials.net_revenue).to eq(0.0)
    end
  end

  describe "#has_data? edge cases" do
    it "returns true when data_confirmed even if no revenue" do
      financials = build(:show_financials, data_confirmed: true, ticket_revenue: 0.0, ticket_count: 0)
      expect(financials.has_data?).to be true
    end

    it "returns true when only expenses present" do
      financials = build(:show_financials, ticket_revenue: 0.0, ticket_count: 0, expenses: 50.0,
                         expense_details: [ { "description" => "Supplies", "amount" => 50.0 } ])
      expect(financials.has_data?).to be true
    end

    it "returns true when ticket_count present but no revenue" do
      financials = build(:show_financials, ticket_count: 10, ticket_revenue: 0.0)
      expect(financials.has_data?).to be true
    end
  end

  describe "complete? consistency with data_confirmed" do
    it "confirmed financials with zero revenue still count as complete" do
      financials = build(:show_financials, :complete, ticket_revenue: 0.0, ticket_count: 0)
      expect(financials.complete?).to be true
    end
  end

  describe "normalized_expense_details" do
    it "returns expense_details as array" do
      financials = build(:show_financials, :with_expense_details)
      details = financials.normalized_expense_details
      expect(details).to be_an(Array)
      expect(details.size).to eq(2)
    end

    it "returns empty array when no details" do
      financials = build(:show_financials, expense_details: nil)
      expect(financials.normalized_expense_details).to eq([])
    end
  end

  describe "normalized_other_revenue_details" do
    it "returns other_revenue_details as array" do
      financials = build(:show_financials, other_revenue_details: [
        { "description" => "Merch", "amount" => 100.0 }
      ])
      details = financials.normalized_other_revenue_details
      expect(details.size).to eq(1)
      expect(details.first["description"]).to eq("Merch")
    end

    it "returns empty array when no details" do
      financials = build(:show_financials, other_revenue_details: nil)
      expect(financials.normalized_other_revenue_details).to eq([])
    end
  end
end
