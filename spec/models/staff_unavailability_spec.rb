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

  describe "reading a mark against an organization's work time regions" do
    let(:organization) { create(:organization) }
    let(:evening_shift) { build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 19, 0), ends_at: Time.zone.local(2026, 6, 1, 23, 0)) }
    let(:afternoon_shift) { build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 13, 0), ends_at: Time.zone.local(2026, 6, 1, 16, 0)) }

    it "an all-day mark blocks any shift" do
      rec = build(:staff_unavailability, scope: :all_day)
      expect(rec).to be_all_day
      expect(rec.covers_shift?(evening_shift)).to be(true)
      expect(rec.covers_shift?(afternoon_shift)).to be(true)
    end

    it "an evening mark blocks an evening shift but not an afternoon one, on the default regions" do
      rec = build(:staff_unavailability, :evening)
      expect(rec.covers_shift?(evening_shift)).to be(true)
      expect(rec.covers_shift?(afternoon_shift)).to be(false)
      expect(build(:staff_unavailability, :afternoon).covers_shift?(evening_shift)).to be(false)
    end

    it "reads the same mark against each organization's own hours" do
      organization.update!(staffing_day_parts: [
        { "key" => "morning", "name" => "Morning", "starts" => "06:00", "ends" => "12:00" },
        { "key" => "evening", "name" => "Evening", "starts" => "18:00", "ends" => "24:00" }
      ])
      early_evening = build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 17, 30), ends_at: Time.zone.local(2026, 6, 1, 20, 0))
      rec = build(:staff_unavailability, :evening)
      # 5:30pm is before this room's Evening starts — and in a gap, so only all day covers it
      expect(rec.covers_shift?(early_evening)).to be(false)
      expect(rec.covers_shift?(evening_shift)).to be(true)
      # A region this room doesn't have blocks nothing here
      expect(build(:staff_unavailability, scope: "afternoon").covers_shift?(afternoon_shift)).to be(false)
      expect(build(:staff_unavailability, scope: "morning").covers_shift?(afternoon_shift)).to be(false)
    end

    it "honours the person's availability mode" do
      entries = [ build(:staff_unavailability, :evening, date: Date.new(2026, 6, 1)) ]
      at = Time.zone.local(2026, 6, 1, 19, 0)
      expect(described_class.unavailable_for?(mode: "unavailable", entries: entries, time: at, organization: organization)).to be(true)
      expect(described_class.unavailable_for?(mode: "available", entries: entries, time: at, organization: organization)).to be(false)
      expect(described_class.unavailable_for?(mode: "available", entries: [], time: at, organization: organization)).to be(true)
    end
  end

  describe "#scope / #scope_label" do
    it "speaks all_day or the region key, and labels by the organization's name for it" do
      organization = create(:organization, staffing_day_parts: [ { "key" => "late", "name" => "Late night", "starts" => "22:00", "ends" => "02:00" } ])
      expect(build(:staff_unavailability, scope: :all_day).scope).to eq("all_day")
      expect(build(:staff_unavailability, scope: :all_day).scope_label).to eq("All day")
      expect(build(:staff_unavailability, scope: "late").scope).to eq("late")
      expect(build(:staff_unavailability, scope: "late").scope_label(organization)).to eq("Late night")
      expect(build(:staff_unavailability, scope: "late").scope_label).to eq("Late")
      expect(build(:staff_unavailability, :evening).scope_label(organization)).to eq("Evening")
    end
  end
end
