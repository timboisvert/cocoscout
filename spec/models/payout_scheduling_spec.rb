# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutScheduling do
  it "is disabled for a manual org" do
    org = build(:organization, payout_schedule: "manual")
    expect(org.payout_schedule_enabled?).to be(false)
    expect(org.next_payout_date).to be_nil
  end

  describe "weekly" do
    let(:org) { build(:organization, payout_schedule: "weekly", payout_schedule_day: 5) } # Friday

    it "finds the next Friday on/after a date" do
      expect(org.next_payout_date(from: Date.new(2026, 7, 13))).to eq(Date.new(2026, 7, 17)) # Mon -> Fri
      expect(org.next_payout_date(from: Date.new(2026, 7, 17))).to eq(Date.new(2026, 7, 17)) # same day
    end

    it "is due only on the scheduled day and not twice" do
      friday = Date.new(2026, 7, 17)
      expect(org.due_for_scheduled_payout?(on: friday)).to be(true)
      expect(org.due_for_scheduled_payout?(on: friday - 1)).to be(false)

      org.last_auto_payout_on = friday
      expect(org.due_for_scheduled_payout?(on: friday)).to be(false)
    end
  end

  describe "monthly" do
    let(:org) { build(:organization, payout_schedule: "monthly", payout_schedule_day: 15) }

    it "rolls to next month once the day has passed" do
      expect(org.next_payout_date(from: Date.new(2026, 7, 10))).to eq(Date.new(2026, 7, 15))
      expect(org.next_payout_date(from: Date.new(2026, 7, 20))).to eq(Date.new(2026, 8, 15))
    end

    it "clamps to the last day for short months" do
      org.payout_schedule_day = 31
      expect(org.next_payout_date(from: Date.new(2026, 2, 1))).to eq(Date.new(2026, 2, 28))
    end
  end
end
