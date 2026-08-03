# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffingHelper, type: :helper do
  describe "#add_business_days" do
    it "skips weekends" do
      # Fri Aug 7, 2026 + 1 business day → Mon Aug 10 (skips Sat/Sun)
      expect(helper.add_business_days(Date.new(2026, 8, 7), 1)).to eq(Date.new(2026, 8, 10))
    end

    it "counts straight through a work week" do
      # Mon Aug 3 + 3 business days → Thu Aug 6
      expect(helper.add_business_days(Date.new(2026, 8, 3), 3)).to eq(Date.new(2026, 8, 6))
    end
  end

  describe "#estimated_deposit_window" do
    it "returns [earliest, latest] using the 2–4 business-day estimate" do
      earliest, latest = helper.estimated_deposit_window(Date.new(2026, 8, 3)) # Monday
      expect(earliest).to eq(Date.new(2026, 8, 5))  # +2 business days → Wed
      expect(latest).to eq(Date.new(2026, 8, 7))    # +4 business days → Fri
      expect(latest).to be > earliest
    end
  end
end
