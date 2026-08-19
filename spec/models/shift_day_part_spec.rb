# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shift, type: :model do
  describe "#day_parts" do
    let(:organization) { create(:organization) }

    def shift_at(hour, min = 0)
      build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, hour, min), ends_at: Time.zone.local(2026, 6, 1, hour, min) + 2.hours)
    end

    it "is every turned-on region the shift starts in — the defaults are Morning, Afternoon, Evening" do
      expect(shift_at(18).day_parts).to eq(%w[evening])
      expect(shift_at(13).day_parts).to eq(%w[afternoon])
      expect(shift_at(8).day_parts).to eq(%w[morning])
      expect(shift_at(3).day_parts).to eq([])
    end

    it "reads overlapping regions the organization has turned on, in catalog order" do
      organization.update!(staffing_day_parts: %w[morning late_morning evening late_evening late_night])
      expect(shift_at(11).day_parts).to eq(%w[morning late_morning])
      expect(shift_at(22, 30).day_parts).to eq(%w[evening late_evening late_night])
      expect(shift_at(0, 30).day_parts).to eq(%w[late_night])
      expect(shift_at(15).day_parts).to eq([])
    end
  end
end
