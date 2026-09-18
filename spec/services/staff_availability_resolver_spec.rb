# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffAvailabilityResolver do
  let(:person) { create(:person) }
  # A Thursday.
  let(:day) { Date.new(2026, 10, 1) }

  def at(date, hour, min = 0)
    Time.zone.local(date.year, date.month, date.day, hour, min)
  end

  def entry(**attrs)
    defaults = { person: person, kind: :dated, polarity: :unavailable, starts_on: day, ends_on: day,
                 starts_minute: 0, ends_minute: 1440, source: :self_reported }
    StaffAvailabilityEntry.create!(defaults.merge(attrs))
  end

  def weekly(wday, **attrs)
    entry(kind: :weekly, day_of_week: wday, starts_on: nil, ends_on: nil, **attrs)
  end

  def verdict(starts_at, ends_at)
    described_class.new([ person.id ], from: starts_at.to_date, to: ends_at.to_date)
                   .verdict(person.id, starts_at, ends_at)
  end

  describe "with nothing said" do
    it "is unknown — treated as free, but not a yes" do
      v = verdict(at(day, 19), at(day, 23))

      expect(v).to be_unknown
      expect(v.can_work_all?).to be(true)
      expect(v.flagged?).to be(false)
    end

    it "is free once they've confirmed, even with no entries" do
      person.update!(availability_confirmed_through: day + 30)

      expect(verdict(at(day, 19), at(day, 23))).to be_free
    end
  end

  describe "a blocked day" do
    before { entry }

    it "blocks a shift inside it" do
      v = verdict(at(day, 19), at(day, 23))

      expect(v).to be_blocked
      expect(v.reasons.size).to eq(1)
    end

    it "leaves the next day alone" do
      expect(verdict(at(day + 1, 19), at(day + 1, 23))).to be_free
    end
  end

  describe "the whole span is read, not just the start" do
    # Blocked from 8pm on. The old model looked at a 4pm start and said fine.
    before { entry(starts_minute: 20 * 60, ends_minute: 1440) }

    it "calls a shift that runs into the blocked stretch partial" do
      v = verdict(at(day, 16), at(day, 23))

      expect(v).to be_partial
      expect(v.available_minutes).to eq(4 * 60)
      expect(v.free_until).to eq(at(day, 20))
      expect(v.free_from).to be_nil
    end
  end

  describe "hour-level and whole-evening in one model" do
    it "reads 'free after 8:30' as partial for a 7pm shift, with when they're free" do
      entry(starts_minute: 0, ends_minute: 20 * 60 + 30)

      v = verdict(at(day, 19), at(day, 23))

      expect(v).to be_partial
      expect(v.free_from).to eq(at(day, 20, 30))
    end

    it "holds two separate blocks in one day, which the old model couldn't" do
      entry(starts_minute: 6 * 60, ends_minute: 10 * 60)
      entry(starts_minute: 21 * 60, ends_minute: 1440)

      expect(verdict(at(day, 12), at(day, 17))).to be_free
      expect(verdict(at(day, 7), at(day, 9))).to be_blocked
      expect(verdict(at(day, 22), at(day, 23))).to be_blocked
    end
  end

  describe "past midnight" do
    it "carries a late-night band onto the next morning" do
      entry(starts_minute: 22 * 60, ends_minute: 26 * 60) # 10pm–2am

      expect(verdict(at(day + 1, 0, 30), at(day + 1, 1, 30))).to be_blocked
      expect(verdict(at(day + 1, 3), at(day + 1, 5))).to be_free
    end

    it "reads a shift that crosses midnight across both days" do
      entry(starts_on: day + 1, ends_on: day + 1) # the whole next day off

      v = verdict(at(day, 22), at(day + 1, 2))

      expect(v).to be_partial
      expect(v.free_until).to eq(at(day + 1, 0))
    end
  end

  describe "weekly patterns and exceptions" do
    it "blocks every matching weekday" do
      weekly(day.wday) # never this weekday

      expect(verdict(at(day, 19), at(day, 22))).to be_blocked
      expect(verdict(at(day + 7, 19), at(day + 7, 22))).to be_blocked
      expect(verdict(at(day + 1, 19), at(day + 1, 22))).to be_free
    end

    it "lets a dated 'available' open up a weekday they're normally out" do
      weekly(day.wday)
      entry(polarity: :available, starts_minute: 18 * 60, ends_minute: 1440)

      expect(verdict(at(day, 19), at(day, 22))).to be_free
      expect(verdict(at(day + 7, 19), at(day + 7, 22))).to be_blocked
    end

    it "lets a dated block override a weekly 'available'" do
      weekly(day.wday, polarity: :available, starts_minute: 17 * 60, ends_minute: 1440)
      entry(starts_minute: 0, ends_minute: 1440)

      expect(verdict(at(day, 19), at(day, 22))).to be_blocked
    end

    it "stops applying a weekly pattern after its end date" do
      weekly(day.wday, ends_on: day)

      expect(verdict(at(day, 19), at(day, 22))).to be_blocked
      expect(verdict(at(day + 7, 19), at(day + 7, 22))).to be_free
    end

    it "blocks a whole range of dates" do
      entry(starts_on: day, ends_on: day + 13) # away two weeks

      expect(verdict(at(day + 5, 19), at(day + 5, 22))).to be_blocked
      expect(verdict(at(day + 14, 19), at(day + 14, 22))).to be_free
    end
  end

  describe "precedence" do
    it "lets a single date beat a longer range" do
      entry(starts_on: day - 3, ends_on: day + 3) # away the week...
      entry(polarity: :available) # ...but this one day works

      expect(verdict(at(day, 19), at(day, 22))).to be_free
    end

    it "lets a narrower band beat a wider one on the same date" do
      entry # all day out
      entry(polarity: :available, starts_minute: 19 * 60, ends_minute: 22 * 60)

      expect(verdict(at(day, 19), at(day, 22))).to be_free
    end

    it "breaks an exact tie toward unavailable" do
      entry(polarity: :available)
      entry(polarity: :unavailable)

      expect(verdict(at(day, 19), at(day, 22))).to be_blocked
    end
  end

  it "answers many people and shifts from one load" do
    other = create(:person)
    entry
    StaffAvailabilityEntry.create!(person: other, kind: :dated, polarity: :unavailable,
                                   starts_on: day + 1, ends_on: day + 1, starts_minute: 0, ends_minute: 1440)

    resolver = described_class.new([ person.id, other.id ], from: day, to: day + 1)

    expect(resolver.verdict(person.id, at(day, 19), at(day, 22))).to be_blocked
    expect(resolver.verdict(other.id, at(day, 19), at(day, 22))).to be_free
    expect(resolver.verdict(other.id, at(day + 1, 19), at(day + 1, 22))).to be_blocked
  end
end
