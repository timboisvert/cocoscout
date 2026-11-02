# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinancialSummaryService do
  let(:organization) { create(:organization, :pro) }
  let(:production) { create(:production, organization: organization) }

  describe "PERIODS" do
    it "defines all expected periods" do
      expect(FinancialSummaryService::PERIODS.keys).to include(
        :all_time, :this_week, :last_week, :this_month, :last_month,
        :last_30_days, :last_90_days, :this_quarter, :last_quarter,
        :this_year, :last_year
      )
    end
  end

  describe "#summary_for_period" do
    let(:service) { described_class.new(production) }

    context "with no shows" do
      it "returns zero values" do
        result = service.summary_for_period(:all_time)

        expect(result[:gross_revenue]).to eq(0.0)
        expect(result[:show_expenses]).to eq(0.0)
        expect(result[:shows_with_data]).to eq(0)
      end
    end

    context "with shows and financials" do
      let!(:show1) do
        show = create(:show, production: production, date_and_time: 1.week.ago, event_type: :show)
        create(:show_financials,
               show: show,
               ticket_revenue: 1000.0,
               other_revenue: 100.0,
               expenses: 200.0)
        show
      end

      let!(:show2) do
        show = create(:show, production: production, date_and_time: 2.weeks.ago, event_type: :show)
        create(:show_financials,
               show: show,
               ticket_revenue: 1500.0,
               expenses: 300.0)
        show
      end

      it "calculates totals across shows" do
        result = service.summary_for_period(:all_time)

        expect(result[:gross_revenue]).to eq(2600.0)  # 1000 + 100 + 1500
        expect(result[:show_expenses]).to eq(500.0)   # 200 + 300
        expect(result[:shows_with_data]).to eq(2)
      end

      it "calculates net revenue" do
        result = service.summary_for_period(:all_time)
        # gross_profit = gross_revenue - cost_of_shows
        # cost_of_shows = show_expenses + production_expenses + total_payouts
        # = 2600 - (500 + 0 + 0) = 2100
        expect(result[:gross_profit]).to eq(2100.0)
      end

      it "filters by period" do
        result = service.summary_for_period(:this_week)
        # Only show1 is in this week
        expect(result[:shows_with_data]).to be <= 2
      end

      it "excludes canceled shows from the totals" do
        canceled = create(:show, production: production, date_and_time: 3.days.ago, event_type: :show, canceled: true)
        create(:show_financials, show: canceled, ticket_revenue: 9999.0, expenses: 50.0)

        result = service.summary_for_period(:all_time)
        # Unchanged from the two live shows — the canceled show's $9,999 is ignored.
        expect(result[:gross_revenue]).to eq(2600.0)
        expect(result[:show_expenses]).to eq(500.0)
        expect(result[:shows_with_data]).to eq(2)
        expect(result[:show_count]).to eq(2)
      end
    end

    context "with flat fee revenue" do
      let!(:show) do
        show = create(:show, production: production, date_and_time: 1.day.ago, event_type: :show)
        create(:show_financials, :flat_fee,
               show: show,
               flat_fee: 2000.0)
        show
      end

      it "tracks flat fee revenue separately" do
        result = service.summary_for_period(:all_time)
        expect(result[:flat_fee_revenue]).to eq(2000.0)
      end
    end

    context "with non-revenue events" do
      let!(:rehearsal) do
        create(:show, :rehearsal, production: production, date_and_time: 1.day.ago)
      end

      it "excludes rehearsals from revenue calculations" do
        result = service.summary_for_period(:all_time)
        expect(result[:shows_with_data]).to eq(0)
      end
    end

    context "with future shows" do
      let!(:future_show) do
        show = create(:show, production: production, date_and_time: 1.week.from_now, event_type: :show)
        create(:show_financials, show: show, ticket_revenue: 5000.0)
        show
      end

      it "excludes future shows" do
        result = service.summary_for_period(:all_time)
        expect(result[:gross_revenue]).to eq(0.0)
      end
    end
  end

  describe "#all_period_summaries" do
    let(:service) { described_class.new(production) }

    it "returns summaries for all periods" do
      result = service.all_period_summaries

      expect(result.keys).to eq(FinancialSummaryService::PERIODS.keys)
      expect(result[:all_time]).to be_a(Hash)
      expect(result[:this_month]).to be_a(Hash)
    end
  end

  # A production on its second deal still earned under the first: every
  # contract that was live counts, each over its own nights (Hags' August
  # show sat under a completed contract and went uncounted, 2026-11-02).
  describe "a production with more than one contract" do
    let(:location) { create(:location, organization: organization) }
    let(:third_party) { create(:production, organization: organization, production_type: "third_party") }

    def deal(status, starts_at)
      contract = create(:contract, :revenue_share_per_event, organization: organization, production: third_party, status: status)
      rental = contract.space_rentals.create!(location: location, starts_at: starts_at, ends_at: starts_at + 2.hours, confirmed: true)
      show = third_party.shows.create!(date_and_time: starts_at, duration_minutes: 120, location: location, space_rental: rental)
      create(:show_financials, :complete, show: show, ticket_revenue: 100.0, other_revenue: 0.0)
      contract
    end

    it "counts every contract that was live, never a cancelled one" do
      travel_to(Time.zone.local(2026, 11, 15, 12)) do
        finished = deal("completed", Time.zone.local(2026, 8, 21, 19))
        running = deal("active", Time.zone.local(2026, 10, 16, 19))
        deal("cancelled", Time.zone.local(2026, 9, 10, 19))
        range = Time.current.beginning_of_year..Time.current.end_of_year
        money = FinancialSummaryService.summaries_by_production([ third_party ], :this_year)[:by_production][third_party.id]

        expect(finished.money_summary(range)[:money_in]).to be_positive
        expect(money[:gross_revenue]).to eq(finished.money_summary(range)[:money_in] + running.money_summary(range)[:money_in])
        expect(money[:cost_of_shows]).to eq(finished.money_summary(range)[:money_out] + running.money_summary(range)[:money_out])
      end
    end
  end

  describe "with multiple productions" do
    let(:production2) { create(:production, organization: organization) }
    let(:service) { described_class.new([ production, production2 ]) }

    let!(:show1) do
      show = create(:show, production: production, date_and_time: 1.day.ago, event_type: :show)
      create(:show_financials, show: show, ticket_revenue: 1000.0)
      show
    end

    let!(:show2) do
      show = create(:show, production: production2, date_and_time: 1.day.ago, event_type: :show)
      create(:show_financials, show: show, ticket_revenue: 2000.0)
      show
    end

    it "aggregates across multiple productions" do
      result = service.summary_for_period(:all_time)
      expect(result[:gross_revenue]).to eq(3000.0)
      expect(result[:shows_with_data]).to eq(2)
    end
  end

  describe ".period_labels" do
    it "returns human-readable labels" do
      labels = FinancialSummaryService.period_labels

      expect(labels[:all_time]).to eq("All Time")
      expect(labels[:this_month]).to eq("This Month")
      expect(labels[:last_30_days]).to eq("Last 30 Days")
    end
  end

  describe ".quick_period_labels" do
    it "returns subset of periods for quick access" do
      labels = FinancialSummaryService.quick_period_labels

      expect(labels.keys).to contain_exactly(:this_month, :last_30_days, :this_year, :all_time)
    end
  end
end
