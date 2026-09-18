# frozen_string_literal: true

require "rails_helper"

# The backfill carries old region marks into time bands. For any shift that sits
# wholly inside one region — the only case the old start-time check got right —
# the new resolver must give the same answer the old model did, in both modes.
RSpec.describe StaffAvailabilityBackfill do
  let(:org) { create(:organization) }
  let(:person) { create(:person) }
  let(:day) { Date.new(2026, 10, 1) }

  def at(hour, min = 0, date: day)
    Time.zone.local(date.year, date.month, date.day, hour, min)
  end

  def mark!(scope, date: day)
    person.staff_unavailabilities.create!(date: date, scope: scope)
  end

  def old_answer(starts_at)
    StaffUnavailability.unavailable_for?(mode: person.availability_mode, entries: person.staff_unavailabilities.reload.to_a,
                                         time: starts_at, organization: org)
  end

  def new_answer(starts_at, ends_at)
    described_class.rebuild!(person)
    StaffAvailabilityResolver.new([ person.id ], from: starts_at.to_date, to: ends_at.to_date)
                             .verdict(person.id, starts_at, ends_at).flagged?
  end

  describe "in the default mode, where marks are days off" do
    it "turns an all-day mark into an all-day block" do
      mark!("all_day")

      expect(new_answer(at(19), at(22))).to eq(old_answer(at(19))).and eq(true)
      expect(new_answer(at(19, date: day + 1), at(22, date: day + 1))).to be(false)
    end

    it "turns a region mark into that region's hours" do
      mark!("evening") # 17:00–24:00

      expect(new_answer(at(19), at(22))).to eq(old_answer(at(19))).and eq(true)
      expect(new_answer(at(9), at(12))).to eq(old_answer(at(9))).and eq(false)
    end

    it "carries an overnight region past midnight instead of wrapping it" do
      mark!("late_night") # 22:00–02:00

      described_class.rebuild!(person)

      entry = person.staff_availability_entries.first
      expect([ entry.starts_minute, entry.ends_minute ]).to eq([ 22 * 60, 26 * 60 ])
    end
  end

  describe "in 'available' mode, where marks are the only workable times" do
    before { person.update!(availability_mode: "available") }

    it "reads an unmarked day as unavailable, as it always did" do
      expect(new_answer(at(19), at(22))).to eq(old_answer(at(19))).and eq(true)
    end

    it "opens exactly the marked region" do
      mark!("evening")

      expect(new_answer(at(19), at(22))).to eq(old_answer(at(19))).and eq(false)
      expect(new_answer(at(9), at(12))).to eq(old_answer(at(9))).and eq(true)
    end

    it "opens a whole marked day" do
      mark!("all_day")

      expect(new_answer(at(9), at(12))).to eq(old_answer(at(9))).and eq(false)
    end
  end

  describe "rebuilding" do
    it "is idempotent" do
      mark!("evening")

      described_class.rebuild!(person)
      described_class.rebuild!(person)

      expect(person.staff_availability_entries.count).to eq(1)
    end

    it "follows a mark being cleared" do
      mark!("evening")
      described_class.rebuild!(person)

      person.staff_unavailabilities.destroy_all
      described_class.rebuild!(person)

      expect(person.staff_availability_entries).to be_empty
    end

    it "never touches entries from any other source" do
      mine = person.staff_availability_entries.create!(kind: :dated, polarity: :available, source: :self_reported,
                                                       starts_on: day, ends_on: day, starts_minute: 0, ends_minute: 1440)
      mark!("evening")

      described_class.rebuild!(person)

      expect(StaffAvailabilityEntry.exists?(mine.id)).to be(true)
    end
  end

  it "rebuilds everyone who has something to carry over" do
    mark!("evening")
    available_only = create(:person, availability_mode: "available")

    expect(described_class.rebuild_all!).to eq(2)
    expect(available_only.staff_availability_entries.count).to eq(7)
  end
end
