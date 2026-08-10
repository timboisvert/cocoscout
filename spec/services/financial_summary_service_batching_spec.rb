# frozen_string_literal: true

require "rails_helper"

# The service used to cost a query or three per show and was called once per
# production by the All Financials grid — so a busy org paid thousands of
# queries for one page. These specs pin the two properties that stops:
# the cost is flat, and the per-production numbers still add up to the total.
#
# The behaviour itself is covered by financial_summary_service_spec.rb and
# financial_summary_service_extended_spec.rb, which were deliberately left
# untouched through the rewrite as the parity contract.
RSpec.describe FinancialSummaryService, "batching" do
  let(:organization) { create(:organization, :pro) }

  def production_with_money!(name, shows: 2, revenue: 100, expense: 10, allocation: nil)
    production = create(:production, organization: organization, name: name)
    shows.times do |i|
      show = create(:show, production: production, event_type: :show, date_and_time: (i + 2).days.ago)
      financials = create(:show_financials, show: show, revenue_type: "ticket_sales",
                                            ticket_revenue: revenue, data_confirmed: true)
      ExpenseItem.create!(show_financials: financials, description: "Sound", amount: expense, category: "venue")
      ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 20)
      next unless allocation

      expense_record = ProductionExpense.create!(production: production, name: "Insurance",
                                                 total_amount: allocation, spread_months: 1)
      ProductionExpenseAllocation.create!(production_expense: expense_record, show: show,
                                          allocated_amount: allocation)
    end
    production
  end

  describe "cost" do
    it "doesn't cost more per production" do
      production_with_money!("One")
      baseline = count_queries { described_class.summaries_by_production(organization.productions.to_a, :all_time) }

      (2..12).each { |i| production_with_money!("Number #{i}") }
      scaled = count_queries { described_class.summaries_by_production(organization.productions.to_a, :all_time) }

      # Eleven more productions, each with shows, financials, expense items,
      # payouts. A per-production pass would cost dozens of queries here.
      expect(scaled - baseline).to be <= 2
    end

    it "doesn't cost more per show" do
      production_with_money!("Small", shows: 1)
      baseline = count_queries { described_class.new(organization.productions.to_a).summary_for_period(:all_time) }

      production_with_money!("Large", shows: 20)
      scaled = count_queries { described_class.new(organization.productions.to_a).summary_for_period(:all_time) }

      expect(scaled - baseline).to be <= 2
    end
  end

  describe "the per-production breakdown" do
    it "gives each production its own figures, and a total that matches" do
      first = production_with_money!("First", shows: 2, revenue: 100, expense: 10)
      second = production_with_money!("Second", shows: 1, revenue: 50, expense: 5)

      result = described_class.summaries_by_production([ first, second ], :all_time)

      expect(result[:by_production][first.id][:gross_revenue]).to eq(200.0)
      expect(result[:by_production][second.id][:gross_revenue]).to eq(50.0)
      expect(result[:total][:gross_revenue]).to eq(250.0)

      expect(result[:by_production][first.id][:show_expenses]).to eq(20.0)
      expect(result[:by_production][second.id][:show_expenses]).to eq(5.0)
      expect(result[:total][:show_expenses]).to eq(25.0)

      expect(result[:by_production][first.id][:show_count]).to eq(2)
      expect(result[:total][:show_count]).to eq(3)
    end

    it "agrees with the single-production service it replaced" do
      production = production_with_money!("Solo", shows: 3, revenue: 80, expense: 12, allocation: 7)
      other = production_with_money!("Noise", shows: 2)

      alone = described_class.new(production).summary_for_period(:all_time)
      batched = described_class.summaries_by_production([ production, other ], :all_time)[:by_production][production.id]

      %i[gross_revenue show_expenses production_expenses total_payouts
         cost_of_shows gross_profit net_income show_count shows_with_data
         ticket_revenue expense_by_category].each do |key|
        expect(batched[key]).to eq(alone[key]), "#{key}: batched #{batched[key].inspect} vs alone #{alone[key].inspect}"
      end
    end

    it "hands back zeros for a production with nothing in the period" do
      empty = create(:production, organization: organization, name: "Nothing Yet")
      result = described_class.summaries_by_production([ empty ], :all_time)

      expect(result[:by_production]).to be_empty
      expect(described_class.empty_summary[:gross_revenue]).to eq(0.0)
      expect(described_class.empty_summary[:show_count]).to eq(0)
    end
  end

  # A row whose expenses live in the legacy JSONB column rather than in
  # expense_items has no rows in the grouped fetch. The batcher has to read that
  # absence as "fall through to the legacy path", not as "expenses of zero".
  describe "rows with no expense_items" do
    it "still counts legacy JSONB expenses" do
      production = create(:production, organization: organization)
      show = create(:show, production: production, event_type: :show, date_and_time: 2.days.ago)
      create(:show_financials, show: show, revenue_type: "ticket_sales", ticket_revenue: 100,
                               data_confirmed: true, expenses: 30)

      summary = described_class.new(production).summary_for_period(:all_time)

      expect(summary[:show_expenses]).to eq(30.0)
      expect(summary[:expense_by_category]["other"]).to eq(30.0)
    end
  end
end
