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

  # A smart day closes when its last show's door closes, by the box office's
  # rule (Ticketing settings → Door; Tim, 2026-11-16: Settle up said every
  # day ran to 6 AM).
  describe ".ends_at" do
    let(:sunday) { Date.new(2026, 11, 15) }
    let(:production) { create(:production, organization: organization) }
    let(:at) { ->(hour, min = 0, day: 15) { Time.zone.local(2026, 11, day, hour, min) } }

    # A fresh answer each time: the close is remembered for a request (Current.day_closes).
    def ends
      Current.reset
      described_class.ends_at(organization, sunday)
    end

    it "closes with the door: 2 AM after an evening show with no end time, an hour after one that has one" do
      create(:show, production: production, date_and_time: at.call(19))
      expect(ends).to eq(at.call(2, 0, day: 16))
      expect(described_class.ended?(organization, sunday, now: at.call(1, 30, day: 16))).to be(false)
      expect(described_class.ended?(organization, sunday, now: at.call(2, 0, day: 16))).to be(true)

      Show.update_all(duration_minutes: 90)
      expect(ends).to eq(at.call(21, 30))
    end

    it "closes 4 hours after a daytime show with no end time, and follows the day's last show" do
      create(:show, production: production, date_and_time: at.call(13))
      expect(ends).to eq(at.call(17))
      create(:show, production: production, date_and_time: at.call(20), duration_minutes: 120)
      expect(ends).to eq(at.call(23))
      # Ready to settle once its door closes, not the next morning.
      expect(SettleUp.open_dates(organization, as_of: at.call(22, 55))).not_to include(sunday)
      expect(SettleUp.open_dates(organization, as_of: at.call(23, 5))).to include(sunday)
    end

    it "runs to the morning hour with no show, and closes at midnight on calendar days" do
      expect(ends).to eq(at.call(6, 0, day: 16))
      organization.update!(settlement_day_mode: "calendar")
      expect(ends).to be_within(1.second).of(at.call(0, 0, day: 16))
    end

    it "says when, on the screens" do
      expect(DayClose.words(at.call(23, 50), sunday)).to eq("11:50 PM")
      expect(DayClose.words(at.call(2, 0, day: 16), sunday)).to eq("2 AM")
      expect(DayClose.words(at.call(18, 0, day: 16), sunday)).to eq("6 PM Monday")
    end
  end
end
