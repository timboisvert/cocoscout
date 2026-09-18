# frozen_string_literal: true

require "rails_helper"

# The writer is the only way answers get in, so these check that each answer
# resolves the way the person meant it — through the resolver, not by
# counting rows.
RSpec.describe StaffAvailabilityWriter do
  let(:person) { create(:person) }
  let(:writer) { described_class.new(person) }
  # A Thursday, safely in the future.
  let(:day) { Date.current.next_occurring(:thursday) + 7 }

  def at(date, hour, min = 0)
    Time.zone.local(date.year, date.month, date.day, hour, min)
  end

  def verdict(starts_at, ends_at)
    StaffAvailabilityResolver.new([ person.id ], from: starts_at.to_date, to: ends_at.to_date)
                             .verdict(person.id, starts_at, ends_at)
  end

  describe "the usual week" do
    it "reads Not at all as out every week" do
      writer.set_weekdays!([ day.wday ], state: "off")

      expect(verdict(at(day, 19), at(day, 22))).to be_blocked
      expect(verdict(at(day + 7, 19), at(day + 7, 22))).to be_blocked
      expect(verdict(at(day + 1, 19), at(day + 1, 22))).to be_free
    end

    it "reads Only certain hours as in for those hours and out for the rest" do
      writer.set_weekdays!([ day.wday ], state: "hours", windows: [ { from: "17:00", to: "00:00" } ])

      expect(verdict(at(day, 19), at(day, 23))).to be_free
      expect(verdict(at(day, 10), at(day, 14))).to be_blocked
      expect(verdict(at(day, 15), at(day, 19))).to be_partial
    end

    it "holds a split day" do
      writer.set_weekdays!([ day.wday ], state: "hours",
                                         windows: [ { from: "09:00", to: "12:00" }, { from: "18:00", to: "22:00" } ])

      expect(verdict(at(day, 9), at(day, 12))).to be_free
      expect(verdict(at(day, 13), at(day, 17))).to be_blocked
      expect(verdict(at(day, 18), at(day, 22))).to be_free
    end

    it "carries a late window past midnight" do
      writer.set_weekdays!([ day.wday ], state: "hours", windows: [ { from: "22:00", to: "02:00" } ])

      expect(verdict(at(day, 22), at(day + 1, 2))).to be_free
    end

    it "answers several days at once, and replaces what was said before" do
      writer.set_weekdays!([ 1, 2, 3 ], state: "off")
      writer.set_weekdays!([ 2 ], state: "anytime")

      week = WorkAvailabilityPicture.new(person).week.index_by(&:wday)
      expect(week[1].answer.state).to eq(:off)
      expect(week[2].answer.state).to eq(:anytime)
      expect(week[3].answer.state).to eq(:off)
    end

    it "turns hours that cover the whole day into Anytime" do
      writer.set_weekdays!([ day.wday ], state: "hours", windows: [ { from: "00:00", to: "00:00" } ])

      expect(person.staff_availability_entries.weekly.pluck(:polarity, :starts_minute, :ends_minute))
        .to eq([ [ "available", 0, 1440 ] ])
    end
  end

  describe "exceptions" do
    it "beats the usual week for its dates only" do
      writer.set_weekdays!([ day.wday ], state: "off")
      writer.save_exception!(starts_on: day, ends_on: day, state: "hours", windows: [ { from: "18:00", to: "23:00" } ])

      expect(verdict(at(day, 19), at(day, 22))).to be_free
      expect(verdict(at(day + 7, 19), at(day + 7, 22))).to be_blocked
    end

    it "blocks a whole trip" do
      writer.save_exception!(starts_on: day, ends_on: day + 10, state: "off", note: "Lisbon")

      expect(verdict(at(day + 4, 19), at(day + 4, 22))).to be_blocked
      expect(person.staff_availability_entries.pluck(:note).uniq).to eq([ "Lisbon" ])
    end

    it "moves when it's edited instead of leaving the old one behind" do
      writer.save_exception!(starts_on: day, ends_on: day, state: "off")
      writer.save_exception!(starts_on: day + 1, ends_on: day + 1, state: "off", replacing: [ day.iso8601, day.iso8601 ])

      expect(person.staff_availability_entries.pluck(:starts_on).uniq).to eq([ day + 1 ])
    end

    it "is removed cleanly" do
      writer.save_exception!(starts_on: day, ends_on: day + 2, state: "off")
      writer.remove_exception!(starts_on: day.iso8601, ends_on: (day + 2).iso8601)

      expect(person.staff_availability_entries).to be_empty
    end

    it "refuses dates already past, and a range that runs backwards" do
      expect { writer.save_exception!(starts_on: Date.current - 3, ends_on: Date.current - 2, state: "off") }
        .to raise_error(described_class::Invalid, /past/)
      expect { writer.save_exception!(starts_on: day, ends_on: day - 1, state: "off") }
        .to raise_error(described_class::Invalid, /before/)
    end
  end

  describe "bad answers" do
    it "needs hours for Only certain hours" do
      expect { writer.set_weekdays!([ 1 ], state: "hours", windows: []) }
        .to raise_error(described_class::Invalid, /hours you can work/)
    end

    it "needs both ends of a window" do
      expect { writer.set_weekdays!([ 1 ], state: "hours", windows: [ { from: "17:00", to: "" } ]) }
        .to raise_error(described_class::Invalid, /start and an end/)
    end

    it "refuses a state it doesn't know" do
      expect { writer.set_weekdays!([ 1 ], state: "sometimes") }.to raise_error(described_class::Invalid)
    end
  end

  describe "confirming" do
    it "counts the person's own changes as checking in" do
      writer.set_weekdays!([ 1 ], state: "off")

      expect(person.reload.availability_confirmed_through).to eq(Date.current + described_class::CONFIRM_DAYS)
    end

    it "doesn't let a manager vouch for someone" do
      manager = create(:user)
      described_class.new(person, source: :manager, created_by: manager).set_weekdays!([ 1 ], state: "off")

      expect(person.reload.availability_confirmed_through).to be_nil
      expect(person.staff_availability_entries.pluck(:source, :created_by_id).uniq).to eq([ [ "manager", manager.id ] ])
    end
  end

  describe ".parse_windows" do
    it "sorts and merges overlapping windows, and runs late ones past midnight" do
      windows = described_class.parse_windows([ { from: "22:00", to: "02:00" }, { from: "09:00", to: "12:00" },
                                                { from: "11:00", to: "13:00" } ])

      expect(windows).to eq([ [ 540, 780 ], [ 1320, 1560 ] ])
    end

    it "skips rows left blank" do
      expect(described_class.parse_windows([ { from: "", to: "" }, { from: "17:00", to: "00:00" } ])).to eq([ [ 1020, 1440 ] ])
    end
  end
end
