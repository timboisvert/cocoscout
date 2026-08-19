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

    it "reads a mark against the regions each organization has turned on — overlapping ones all count" do
      organization.update!(staffing_day_parts: %w[morning late_evening late_night])
      late = build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 1, 22, 30), ends_at: Time.zone.local(2026, 6, 2, 1, 0))
      expect(build(:staff_unavailability, scope: "late_evening").covers_shift?(late)).to be(true)
      expect(build(:staff_unavailability, scope: "late_night").covers_shift?(late)).to be(true)
      # 7pm is in no region this room offers, so only all day covers it
      expect(build(:staff_unavailability, scope: "late_evening").covers_shift?(evening_shift)).to be(false)
      # A region this room hasn't turned on blocks nothing here, even though it's in the catalog
      expect(build(:staff_unavailability, :evening).covers_shift?(evening_shift)).to be(false)
      expect(build(:staff_unavailability, :afternoon).covers_shift?(afternoon_shift)).to be(false)
      # A shift starting past midnight still reads as Late night
      small_hours = build(:shift, organization: organization, starts_at: Time.zone.local(2026, 6, 2, 1, 0), ends_at: Time.zone.local(2026, 6, 2, 3, 0))
      expect(build(:staff_unavailability, scope: "late_night", date: Date.new(2026, 6, 2)).covers_shift?(small_hours)).to be(true)
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
    it "speaks all_day or the region key, and labels by the catalog name" do
      organization = create(:organization, staffing_day_parts: %w[late_night])
      expect(build(:staff_unavailability, scope: :all_day).scope).to eq("all_day")
      expect(build(:staff_unavailability, scope: :all_day).scope_label).to eq("All day")
      expect(build(:staff_unavailability, scope: "late_night").scope).to eq("late_night")
      expect(build(:staff_unavailability, scope: "late_night").scope_label(organization)).to eq("Late night")
      expect(build(:staff_unavailability, scope: "late_night").scope_label).to eq("Late Night")
      expect(build(:staff_unavailability, :evening).scope_label(organization)).to eq("Evening")
    end
  end
end
