# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shift, type: :model do
  describe "#day_part" do
    it "is :evening when the shift starts at or after 5pm" do
      shift = build(:shift, starts_at: Time.zone.local(2026, 6, 1, 18, 0), ends_at: Time.zone.local(2026, 6, 1, 22, 0))
      expect(shift.day_part).to eq(:evening)
    end

    it "is :day when the shift starts before 5pm" do
      shift = build(:shift, starts_at: Time.zone.local(2026, 6, 1, 13, 0), ends_at: Time.zone.local(2026, 6, 1, 16, 0))
      expect(shift.day_part).to eq(:day)
    end
  end
end
