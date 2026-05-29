# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffUnavailability, type: :model do
  describe "validations" do
    it "is valid with the factory" do
      expect(build(:staff_unavailability)).to be_valid
    end

    it "requires a date" do
      expect(build(:staff_unavailability, date: nil)).not_to be_valid
    end

    it "enforces one record per person per date" do
      person = create(:person)
      create(:staff_unavailability, person: person, date: Date.new(2026, 6, 1))
      dup = build(:staff_unavailability, person: person, date: Date.new(2026, 6, 1))
      expect(dup).not_to be_valid
    end

    it "allows the same date for different people" do
      date = Date.new(2026, 6, 1)
      create(:staff_unavailability, person: create(:person), date: date)
      expect(build(:staff_unavailability, person: create(:person), date: date)).to be_valid
    end
  end

  describe ".day_part_for" do
    it "treats times at or after 5pm as evening" do
      expect(described_class.day_part_for(Time.zone.local(2026, 6, 1, 17, 0))).to eq(:evening)
      expect(described_class.day_part_for(Time.zone.local(2026, 6, 1, 21, 30))).to eq(:evening)
    end

    it "treats times before 5pm as day" do
      expect(described_class.day_part_for(Time.zone.local(2026, 6, 1, 16, 59))).to eq(:day)
      expect(described_class.day_part_for(Time.zone.local(2026, 6, 1, 9, 0))).to eq(:day)
    end
  end

  describe "#covers_day_part?" do
    it "all_day covers both day and evening" do
      rec = build(:staff_unavailability, scope: :all_day)
      expect(rec.covers_day_part?(:day)).to be(true)
      expect(rec.covers_day_part?(:evening)).to be(true)
    end

    it "day_shifts covers only day" do
      rec = build(:staff_unavailability, scope: :day_shifts)
      expect(rec.covers_day_part?(:day)).to be(true)
      expect(rec.covers_day_part?(:evening)).to be(false)
    end

    it "evening_shifts covers only evening" do
      rec = build(:staff_unavailability, scope: :evening_shifts)
      expect(rec.covers_day_part?(:evening)).to be(true)
      expect(rec.covers_day_part?(:day)).to be(false)
    end
  end

  describe "#covers_shift?" do
    let(:evening_shift) { build(:shift, starts_at: Time.zone.local(2026, 6, 1, 19, 0), ends_at: Time.zone.local(2026, 6, 1, 23, 0)) }
    let(:afternoon_shift) { build(:shift, starts_at: Time.zone.local(2026, 6, 1, 13, 0), ends_at: Time.zone.local(2026, 6, 1, 16, 0)) }

    it "evening_shifts unavailability blocks an evening shift but not an afternoon one" do
      rec = build(:staff_unavailability, scope: :evening_shifts)
      expect(rec.covers_shift?(evening_shift)).to be(true)
      expect(rec.covers_shift?(afternoon_shift)).to be(false)
    end

    it "all_day blocks any shift" do
      rec = build(:staff_unavailability, scope: :all_day)
      expect(rec.covers_shift?(evening_shift)).to be(true)
      expect(rec.covers_shift?(afternoon_shift)).to be(true)
    end
  end

  describe "#scope_label" do
    it "uses friendly labels" do
      expect(build(:staff_unavailability, scope: :all_day).scope_label).to eq("All day")
      expect(build(:staff_unavailability, scope: :day_shifts).scope_label).to eq("Afternoon")
      expect(build(:staff_unavailability, scope: :evening_shifts).scope_label).to eq("Evening")
    end
  end
end
