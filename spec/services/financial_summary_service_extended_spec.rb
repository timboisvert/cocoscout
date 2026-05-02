# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinancialSummaryService, "extended tests", type: :service do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }

  describe "summary calculations" do
    context "with shows spanning multiple event types" do
      before do
        # Revenue event
        show1 = create(:show, production: production, date_and_time: 2.days.ago, event_type: "show")
        create(:show_financials, :complete, show: show1, ticket_revenue: 1000.0, expenses: 100.0)

        # Rehearsal (non-revenue) - should be excluded
        create(:show, :rehearsal, production: production, date_and_time: 3.days.ago)

        # Meeting (non-revenue) - should be excluded
        create(:show, :meeting, production: production, date_and_time: 4.days.ago)
      end

      it "only includes revenue events in calculations" do
        result = described_class.new(production).summary_for_period(:all_time)
        expect(result[:shows_with_data]).to eq(1)
        expect(result[:gross_revenue]).to eq(1000.0)
      end
    end

    context "with mixed revenue types across shows" do
      before do
        ticket_show = create(:show, production: production, date_and_time: 1.day.ago, event_type: "show")
        create(:show_financials, :complete, show: ticket_show, ticket_revenue: 800.0)

        flat_show = create(:show, production: production, date_and_time: 2.days.ago, event_type: "show")
        create(:show_financials, :complete, :flat_fee, show: flat_show, flat_fee: 1500.0)
      end

      it "tracks ticket and flat fee revenue separately" do
        result = described_class.new(production).summary_for_period(:all_time)
        expect(result[:ticket_revenue]).to eq(800.0)
        expect(result[:flat_fee_revenue]).to eq(1500.0)
        expect(result[:gross_revenue]).to eq(2300.0)
      end
    end

    context "with other revenue" do
      before do
        show = create(:show, production: production, date_and_time: 1.day.ago, event_type: "show")
        create(:show_financials, :complete, show: show, ticket_revenue: 500.0, other_revenue: 200.0)
      end

      it "includes other revenue in gross total" do
        result = described_class.new(production).summary_for_period(:all_time)
        expect(result[:gross_revenue]).to eq(700.0)
        expect(result[:other_revenue]).to eq(200.0)
      end
    end

    context "with expenses" do
      before do
        show = create(:show, production: production, date_and_time: 1.day.ago, event_type: "show")
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, expenses: 300.0)
      end

      it "calculates cost breakdown" do
        result = described_class.new(production).summary_for_period(:all_time)
        expect(result[:show_expenses]).to eq(300.0)
        expect(result[:cost_of_shows]).to eq(300.0) # expenses + 0 production expenses + 0 payouts
      end

      it "calculates gross profit" do
        result = described_class.new(production).summary_for_period(:all_time)
        expect(result[:gross_profit]).to eq(700.0)
      end

      it "calculates gross margin percentage" do
        result = described_class.new(production).summary_for_period(:all_time)
        expect(result[:gross_margin]).to eq(70.0)
      end
    end

    context "with payouts" do
      before do
        show = create(:show, production: production, date_and_time: 1.day.ago, event_type: "show")
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, expenses: 100.0)
        create(:show_payout, show: show, total_payout: 400.0, calculated_at: Time.current)
      end

      it "includes payouts in cost of shows" do
        result = described_class.new(production).summary_for_period(:all_time)
        expect(result[:total_payouts]).to eq(400.0)
        expect(result[:cost_of_shows]).to eq(500.0) # 100 expenses + 400 payouts
        expect(result[:gross_profit]).to eq(500.0) # 1000 - 500
      end
    end

    context "average revenue per show" do
      before do
        3.times do |i|
          show = create(:show, production: production, date_and_time: (i + 1).days.ago, event_type: "show")
          create(:show_financials, :complete, show: show, ticket_revenue: (i + 1) * 300.0)
        end
      end

      it "calculates average correctly" do
        result = described_class.new(production).summary_for_period(:all_time)
        # Revenue: 300 + 600 + 900 = 1800, avg = 600
        expect(result[:average_revenue_per_show]).to eq(600.0)
      end
    end

    context "with zero revenue" do
      it "handles zero division for margin" do
        result = described_class.new(production).summary_for_period(:all_time)
        expect(result[:gross_margin]).to eq(0)
        expect(result[:average_revenue_per_show]).to eq(0)
      end
    end
  end

  describe "period filtering" do
    let(:service) { described_class.new(production) }

    before do
      # Show from this month
      show_recent = create(:show, production: production, date_and_time: Time.current.beginning_of_month + 1.day, event_type: "show")
      create(:show_financials, :complete, show: show_recent, ticket_revenue: 500.0)

      # Show from last month
      show_last_month = create(:show, production: production,
                                date_and_time: 1.month.ago.beginning_of_month + 5.days,
                                event_type: "show")
      create(:show_financials, :complete, show: show_last_month, ticket_revenue: 300.0)

      # Show from last year
      show_old = create(:show, production: production,
                         date_and_time: 1.year.ago - 1.day,
                         event_type: "show")
      create(:show_financials, :complete, show: show_old, ticket_revenue: 200.0)
    end

    it "all_time includes everything" do
      result = service.summary_for_period(:all_time)
      expect(result[:shows_with_data]).to eq(3)
      expect(result[:gross_revenue]).to eq(1000.0)
    end

    it "this_month only includes recent shows" do
      result = service.summary_for_period(:this_month)
      expect(result[:shows_with_data]).to eq(1)
      expect(result[:gross_revenue]).to eq(500.0)
    end

    it "last_month only includes last month shows" do
      result = service.summary_for_period(:last_month)
      expect(result[:shows_with_data]).to eq(1)
      expect(result[:gross_revenue]).to eq(300.0)
    end

    it "this_year includes this year's shows" do
      result = service.summary_for_period(:this_year)
      expect(result[:gross_revenue]).to be >= 500.0 # At least the recent show
    end
  end

  describe "backward compatibility" do
    before do
      show = create(:show, production: production, date_and_time: 1.day.ago, event_type: "show")
      create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, expenses: 200.0)
    end

    it "includes legacy keys" do
      result = described_class.new(production).summary_for_period(:all_time)
      expect(result[:total_revenue]).to eq(result[:gross_revenue])
      expect(result[:total_expenses]).to eq(result[:show_expenses])
      expect(result[:net_profit]).to eq(result[:gross_profit])
      expect(result[:profit_margin]).to eq(result[:gross_margin])
      expect(result[:retained]).to eq(result[:net_income])
    end
  end

  describe "expense category tracking" do
    before do
      show = create(:show, production: production, date_and_time: 1.day.ago, event_type: "show")
      create(:show_financials, :complete, show: show,
             ticket_revenue: 1000.0,
             expense_details: [
               { "description" => "Sound tech", "amount" => 100.0, "category" => "labor" },
               { "description" => "Props", "amount" => 50.0, "category" => "supplies" },
               { "description" => "Lighting", "amount" => 75.0, "category" => "labor" }
             ])
    end

    it "groups expenses by category" do
      result = described_class.new(production).summary_for_period(:all_time)
      expect(result[:expense_by_category]["labor"]).to eq(175.0)
      expect(result[:expense_by_category]["supplies"]).to eq(50.0)
    end
  end
end
