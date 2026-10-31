# frozen_string_literal: true

require "rails_helper"

RSpec.describe SettlementDay do
  let(:organization) { create(:organization) }

  describe ".day_for" do
    it "keeps the small hours with the night before on smart days" do
      friday_late = Time.zone.local(2026, 10, 24, 23, 30)
      saturday_small = Time.zone.local(2026, 10, 25, 1, 40)
      saturday_morning = Time.zone.local(2026, 10, 25, 6, 0)
      expect(described_class.day_for(organization, friday_late)).to eq(Date.new(2026, 10, 24))
      expect(described_class.day_for(organization, saturday_small)).to eq(Date.new(2026, 10, 24))
      expect(described_class.day_for(organization, saturday_morning)).to eq(Date.new(2026, 10, 25))
    end

    it "cuts at midnight on calendar days" do
      organization.update!(settlement_day_mode: "calendar")
      expect(described_class.day_for(organization, Time.zone.local(2026, 10, 25, 1, 40))).to eq(Date.new(2026, 10, 25))
    end

    it "follows the morning hour" do
      organization.update!(settlement_day_starts_at: 4)
      expect(described_class.day_for(organization, Time.zone.local(2026, 10, 25, 4, 30))).to eq(Date.new(2026, 10, 25))
      expect(described_class.day_for(organization, Time.zone.local(2026, 10, 25, 3, 30))).to eq(Date.new(2026, 10, 24))
    end
  end

  describe ".ended?" do
    it "is over once the next morning comes" do
      date = Date.new(2026, 10, 24)
      expect(described_class.ended?(organization, date, now: Time.zone.local(2026, 10, 25, 2, 0))).to be(false)
      expect(described_class.ended?(organization, date, now: Time.zone.local(2026, 10, 25, 6, 0))).to be(true)
    end
  end
end
