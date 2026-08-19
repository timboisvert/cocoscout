# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shift, type: :model do
  describe "#day_part" do
    let(:organization) { create(:organization) }

    it "is the key of the organization's work time region the shift starts in — the defaults split at 5pm" do
      evening = build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 18, 0), ends_at: Time.zone.local(2026, 6, 1, 22, 0))
      afternoon = build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 13, 0), ends_at: Time.zone.local(2026, 6, 1, 16, 0))
      expect(evening.day_part).to eq("evening")
      expect(afternoon.day_part).to eq("afternoon")
    end

    it "reads the organization's own regions, and is nil in a gap between them" do
      organization.update!(staffing_day_parts: [
        { "key" => "morning", "name" => "Morning", "starts" => "06:00", "ends" => "12:00" },
        { "key" => "late", "name" => "Late", "starts" => "22:00", "ends" => "02:00" }
      ])
      expect(build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 8, 0), ends_at: Time.zone.local(2026, 6, 1, 11, 0)).day_part).to eq("morning")
      expect(build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 0, 30), ends_at: Time.zone.local(2026, 6, 1, 3, 0)).day_part).to eq("late")
      expect(build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 15, 0), ends_at: Time.zone.local(2026, 6, 1, 17, 0)).day_part).to be_nil
    end
  end
end
