# frozen_string_literal: true

require "rails_helper"

RSpec.describe CastingConflicts do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:other_production) { create(:production, organization: org) }
  let(:person) { create(:person) }

  # 8pm–10pm next Friday, explicit so overlap math is deterministic.
  let(:showtime) { Time.zone.local(2026, 10, 2, 20, 0) }
  let(:show) { create(:show, production: production, date_and_time: showtime, duration_minutes: 120) }

  def cast(person, in_show:)
    role = create(:role, production: in_show.production, show_id: in_show.use_custom_roles? ? in_show.id : nil)
    create(:show_person_role_assignment, show: in_show, role: role, assignable: person)
  end

  describe ".for_member overlap detection" do
    it "flags an overlapping assignment in another production of the same org" do
      other = create(:show, production: other_production, date_and_time: showtime + 1.hour, duration_minutes: 120)
      cast(person, in_show: other)

      conflicts = described_class.for_member(show: show, assignable: person)
      expect(conflicts.length).to eq(1)
      expect(conflicts.first.kind).to eq(:overlap)
      expect(conflicts.first.message).to include("already cast in")
      expect(conflicts.first.message).to include("overlaps this show")
    end

    it "ignores back-to-back shows (1-minute buffer)" do
      other = create(:show, production: other_production, date_and_time: showtime + 2.hours, duration_minutes: 60)
      cast(person, in_show: other)

      expect(described_class.for_member(show: show, assignable: person)).to be_empty
    end

    it "uses the 120-minute default when the other show has no duration" do
      # Starts 1h before ours; default 2h length means it runs into our slot.
      other = create(:show, production: other_production, date_and_time: showtime - 1.hour, duration_minutes: nil)
      cast(person, in_show: other)

      expect(described_class.for_member(show: show, assignable: person)).not_to be_empty
    end

    it "starts the busy window at call time when one is set" do
      # Our show 8–10pm. Their show 10:30pm, but with a 9:30pm call time.
      other = create(:show, production: other_production, date_and_time: showtime + 2.5.hours,
                            duration_minutes: 60, call_time: showtime + 1.5.hours, call_time_enabled: true)
      cast(person, in_show: other)

      expect(described_class.for_member(show: show, assignable: person)).not_to be_empty
    end

    it "ignores canceled shows" do
      other = create(:show, production: other_production, date_and_time: showtime, duration_minutes: 120, canceled: true)
      cast(person, in_show: other)

      expect(described_class.for_member(show: show, assignable: person)).to be_empty
    end

    it "cannot see other organizations' shows" do
      foreign = create(:show, production: create(:production), date_and_time: showtime, duration_minutes: 120)
      cast(person, in_show: foreign)

      expect(described_class.for_member(show: show, assignable: person)).to be_empty
    end

    it "never conflicts a member already cast in the target show" do
      cast(person, in_show: show)
      other = create(:show, production: other_production, date_and_time: showtime, duration_minutes: 120)
      cast(person, in_show: other)

      expect(described_class.for_member(show: show, assignable: person)).to be_empty
    end

    it "ignores non-overlapping assignments" do
      other = create(:show, production: other_production, date_and_time: showtime + 1.week)
      cast(person, in_show: other)

      expect(described_class.for_member(show: show, assignable: person)).to be_empty
    end
  end

  describe "declared unavailability" do
    it "flags a member who marked themselves unavailable, with their note" do
      create(:show_availability, :unavailable, show: show, available_entity: person, note: "Out of town")

      conflicts = described_class.for_member(show: show, assignable: person)
      expect(conflicts.length).to eq(1)
      expect(conflicts.first.kind).to eq(:unavailable)
      expect(conflicts.first.message).to include("unavailable")
      expect(conflicts.first.message).to include("Out of town")
    end

    it "does not flag available or unset members" do
      create(:show_availability, :available, show: show, available_entity: person)

      expect(described_class.for_member(show: show, assignable: person)).to be_empty
    end
  end

  describe ".busy_map" do
    it "returns keyed conflicts only for members who have them" do
      busy = create(:person)
      free = create(:person)
      unavailable = create(:person)
      other = create(:show, production: other_production, date_and_time: showtime, duration_minutes: 120)
      cast(busy, in_show: other)
      create(:show_availability, :unavailable, show: show, available_entity: unavailable)

      map = described_class.busy_map(show: show, members: [ busy, free, unavailable ])

      expect(map.keys).to contain_exactly("Person_#{busy.id}", "Person_#{unavailable.id}")
      expect(map["Person_#{busy.id}"].map(&:kind)).to eq([ :overlap ])
      expect(map["Person_#{unavailable.id}"].map(&:kind)).to eq([ :unavailable ])
    end

    it "still reports overlaps for members cast in the target show (passive indicators)" do
      cast(person, in_show: show)
      other = create(:show, production: other_production, date_and_time: showtime, duration_minutes: 120)
      cast(person, in_show: other)

      map = described_class.busy_map(show: show, members: [ person ])
      expect(map["Person_#{person.id}"].map(&:kind)).to eq([ :overlap ])
    end

    it "matches groups as groups" do
      group = create(:group)
      other = create(:show, production: other_production, date_and_time: showtime, duration_minutes: 120)
      role = create(:role, production: other_production)
      create(:show_person_role_assignment, show: other, role: role, assignable: group)

      map = described_class.busy_map(show: show, members: [ group ])
      expect(map.keys).to eq([ "Group_#{group.id}" ])
    end

    it "is empty for a show with no date" do
      dateless = build(:show, production: production, date_and_time: nil)
      dateless.save(validate: false)

      expect(described_class.busy_map(show: dateless, members: [ person ])).to be_empty
    end
  end
end
