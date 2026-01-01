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

  describe ".invalidate" do
    it "clears the cache for the production" do
      # Generate to populate cache
      service.generate

      # Should not raise
      expect { described_class.invalidate(production) }.not_to raise_error
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
