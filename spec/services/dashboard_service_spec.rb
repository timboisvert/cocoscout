# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardService do
  let(:production) { create(:production) }
  let(:service) { described_class.new(production) }

  describe "#generate" do
    it "returns a hash with dashboard data" do
      result = service.generate

      expect(result).to be_a(Hash)
      expect(result).to have_key(:open_calls)
      expect(result).to have_key(:upcoming_shows)
      expect(result).to have_key(:availability_summary)
      expect(result).to have_key(:open_vacancies)
    end

    it "caches the result" do
      first_result = service.generate
      second_result = service.generate

      expect(first_result).to eq(second_result)
    end
  end

  describe ".generate_all" do
    let(:other_production) { create(:production, organization: create(:organization, :pro)) }

    it "returns payloads keyed by production id" do
      results = described_class.generate_all([ production, other_production ])

      expect(results.keys).to contain_exactly(production.id, other_production.id)
      expect(results[production.id]).to have_key(:open_calls)
      expect(results[other_production.id]).to have_key(:upcoming_shows)
    end

    it "returns an empty hash for no productions" do
      expect(described_class.generate_all([])).to eq({})
    end

    it "writes cache entries the single-production path reads (key parity)" do
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)

      create(:show, production: production, date_and_time: 1.week.from_now)
      create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now)

      bulk = described_class.generate_all([ production, other_production ])

      # If the bulk keys matched, the single path must be a pure cache hit —
      # no regeneration, identical payloads.
      [ production, other_production ].each do |prod|
        expect_any_instance_of(described_class).not_to receive(:build_payload)
        expect(described_class.new(prod).generate).to eq(bulk[prod.id])
      end
    end
  end

  describe "open_calls_summary" do
    context "with no audition cycle" do
      it "returns empty summary" do
        result = service.generate

        expect(result[:open_calls][:total_open]).to eq(0)
        expect(result[:open_calls][:with_auditionees]).to be_empty
      end
    end

    context "with active audition cycle" do
      let!(:audition_cycle) do
        create(:audition_cycle,
          production: production,
          opens_at: 1.day.ago,
          closes_at: 1.week.from_now
        )
      end

      it "returns open call summary" do
        Rails.cache.clear
        result = service.generate

        expect(result[:open_calls][:total_open]).to eq(1)
      end
    end
  end

  describe "upcoming_shows" do
    let!(:upcoming_show) do
      create(:show, production: production, date_and_time: 1.week.from_now)
    end

    let!(:past_show) do
      create(:show, production: production, date_and_time: 1.week.ago)
    end

    it "includes only future shows" do
      Rails.cache.clear
      result = service.generate

      show_ids = result[:upcoming_shows].map { |s| s[:show].id }
      expect(show_ids).to include(upcoming_show.id)
      expect(show_ids).not_to include(past_show.id)
    end
  end

  describe "open_vacancies" do
    let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }
    let!(:role) { create(:role, show: show) }
    let!(:vacancy) { create(:role_vacancy, role: role, show: show, status: :open) }

    it "includes open vacancies for future shows" do
      Rails.cache.clear
      result = service.generate

      vacancy_ids = result[:open_vacancies].map { |v| v[:vacancy].id }
      expect(vacancy_ids).to include(vacancy.id)
    end
  end
end
