# frozen_string_literal: true

require "rails_helper"

# What the writer stores has to read back as what the person said, or the
# page would show them something other than their own answer.
RSpec.describe WorkAvailabilityPicture do
  let(:person) { create(:person) }
  let(:writer) { StaffAvailabilityWriter.new(person) }
  let(:day) { Date.current.next_occurring(:thursday) + 7 }

  def picture = described_class.new(person)

  def week = picture.week.index_by(&:wday)

  it "reads an untouched week as Anytime that nobody has said" do
    expect(week.values.map { |d| d.answer.label }.uniq).to eq([ "Anytime" ])
    expect(week.values.none? { |d| d.answer.said }).to be(true)
    expect(picture.anything_said?).to be(false)
  end

  it "reads back each of the three answers, in the words they were set in" do
    writer.set_weekdays!([ 1 ], state: "off")
    writer.set_weekdays!([ 2 ], state: "anytime")
    writer.set_weekdays!([ 3 ], state: "hours", windows: [ { from: "20:30", to: "00:00" } ])
    writer.set_weekdays!([ 4 ], state: "hours", windows: [ { from: "00:00", to: "17:00" } ])
    writer.set_weekdays!([ 5 ], state: "hours", windows: [ { from: "22:00", to: "02:00" } ])

    expect(week[1].answer.label).to eq("Not working")
    expect(week[2].answer.label).to eq("Anytime")
    expect(week[3].answer.label).to eq("After 8:30 PM")
    expect(week[4].answer.label).to eq("Until 5:00 PM")
    expect(week[5].answer.label).to eq("10:00 PM – 2:00 AM")
    # And back into the sheet's time fields the way they went in.
    expect(week[5].answer.window_fields).to eq([ { from: "22:00", to: "02:00" } ])
  end

  it "collapses runs of the same answer for the summary" do
    writer.set_weekdays!([ 1, 2, 3, 4 ], state: "off")
    writer.set_weekdays!([ 5, 6 ], state: "hours", windows: [ { from: "17:00", to: "00:00" } ])

    expect(picture.week_summary).to eq([
      [ "Mon – Thu", "Not working" ],
      [ "Fri, Sat", "After 5:00 PM" ],
      [ "Sun", "Anytime" ]
    ])
  end

  it "lists exceptions soonest first, and drops ones already over" do
    writer.save_exception!(starts_on: day + 5, ends_on: day + 9, state: "off", note: "Away")
    writer.save_exception!(starts_on: day, ends_on: day, state: "hours", windows: [ { from: "18:00", to: "22:00" } ])
    StaffAvailabilityEntry.create!(person: person, kind: :dated, polarity: :unavailable, source: :self_reported,
                                   starts_on: Date.current - 10, ends_on: Date.current - 9)

    exceptions = picture.exceptions
    expect(exceptions.map(&:starts_on)).to eq([ day, day + 5 ])
    expect(exceptions.first.answer.label).to eq("6:00 PM – 10:00 PM")
    expect(exceptions.last.answer.label).to eq("Not working")
    expect(exceptions.last.note).to eq("Away")
  end

  # Carried over from the old day marks: an "evening" mark only ever spoke
  # for the evening. It says exactly that, and edits as the hours it left.
  it "reads an old-style evening mark literally" do
    StaffAvailabilityEntry.create!(person: person, kind: :dated, polarity: :unavailable, source: :migrated,
                                   starts_on: day, ends_on: day, starts_minute: 17 * 60, ends_minute: 1440)

    answer = picture.exceptions.first.answer
    expect(answer.state).to eq(:limited)
    expect(answer.label).to eq("Can't work 5:00 PM – 12:00 AM")
    expect(answer.editable_state).to eq("hours")
    expect(answer.window_fields).to eq([ { from: "00:00", to: "17:00" } ])
  end

  it "names the manager who set something" do
    manager = create(:user)
    StaffAvailabilityWriter.new(person, source: :manager, created_by: manager).set_weekdays!([ 1 ], state: "off")

    expect(week[1].answer.set_by).to eq(manager)
  end
end
