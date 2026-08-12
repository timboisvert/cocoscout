# frozen_string_literal: true

require "rails_helper"

RSpec.describe SchedulingRuleMatcher do
  let(:organization) { create(:organization, :pro) }
  let(:production) { create(:production, organization: organization) }
  let(:week_start) { Date.current.beginning_of_week + 1.week } # a fully future week
  let(:tuesday) { week_start + 1 }
  let(:thursday) { week_start + 3 }

  let(:tech_role) { create(:house_role, organization: organization, name: "Tech", role_type: :show_specific) }
  let(:bar_role)  { create(:house_role, organization: organization, name: "Bartender", role_type: :house) }

  def staff!(person, *roles)
    member = OrganizationStaffMember.find_or_create_by!(organization: organization, person: person)
    roles.each { |r| create(:staff_role_qualification, organization_staff_member: member, house_role: r) }
    member
  end

  def matcher
    described_class.new(organization: organization, week_start: week_start)
  end

  describe "production-anchored rules" do
    let(:person) { create(:person, name: "Haley") }
    let!(:early_show) { create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20), duration_minutes: 90) }
    let!(:late_show)  { create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 21, min: 30), duration_minutes: 90) }

    before { staff!(person, tech_role, bar_role) }

    it "offers a per-show role once per show, at the show's own hours" do
      rule = create(:scheduling_rule, organization: organization, person: person,
                                      house_role: tech_role, production: production)

      matches = matcher.matches
      expect(matches.size).to eq(2)
      expect(matches.map(&:show)).to contain_exactly(early_show, late_show)
      first = matches.find { |m| m.show == early_show }
      expect(first.starts_at).to eq(early_show.date_and_time)
      expect(first.ends_at).to eq(early_show.ends_at)
      expect(first.key).to eq("#{rule.id}:#{tuesday.iso8601}:#{early_show.id}")
      expect(first).to be_prechecked
    end

    it "offers a house role once per day, spanning the evening, with no show anchor" do
      create(:scheduling_rule, organization: organization, person: person,
                               house_role: bar_role, production: production)

      matches = matcher.matches
      expect(matches.size).to eq(1)
      match = matches.first
      expect(match.show).to be_nil
      expect(match.starts_at).to eq(early_show.date_and_time)
      expect(match.ends_at).to eq(late_show.ends_at)
    end

    it "ignores shows of other productions and canceled shows" do
      create(:show, production: create(:production, organization: organization),
                    date_and_time: thursday.in_time_zone.change(hour: 20))
      create(:show, production: production, canceled: true,
                    date_and_time: thursday.in_time_zone.change(hour: 20))
      create(:scheduling_rule, organization: organization, person: person,
                               house_role: tech_role, production: production)

      expect(matcher.matches.map(&:date).uniq).to eq([ tuesday ])
    end
  end

  describe "weekday rules" do
    let(:person) { create(:person, name: "Camille") }

    before { staff!(person, bar_role) }

    def weekday_rule(starts: "18:00", ends: "22:00")
      create(:scheduling_rule, :weekday, organization: organization, person: person,
                                         house_role: bar_role, day_of_week: 4,
                                         starts_local_time: starts, ends_local_time: ends)
    end

    it "offers the rule's window on its weekday when that day has an event" do
      create(:show, production: production, date_and_time: thursday.in_time_zone.change(hour: 20))
      weekday_rule

      matches = matcher.matches
      expect(matches.size).to eq(1)
      match = matches.first
      expect(match.date).to eq(thursday)
      expect(match.starts_at).to eq(thursday.in_time_zone.change(hour: 18))
      expect(match.ends_at).to eq(thursday.in_time_zone.change(hour: 22))
      expect(match.show).to be_nil
    end

    it "is skipped entirely when the weekday has no events" do
      create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20))
      weekday_rule

      expect(matcher.matches).to be_empty
    end

    it "rolls an end time at or before the start past midnight" do
      create(:show, production: production, date_and_time: thursday.in_time_zone.change(hour: 20))
      weekday_rule(starts: "21:00", ends: "01:00")

      match = matcher.matches.first
      expect(match.ends_at).to eq((thursday + 1).in_time_zone.change(hour: 1))
    end
  end

  describe "availability" do
    let(:person) { create(:person, name: "Camille") }
    let!(:show) { create(:show, production: production, date_and_time: thursday.in_time_zone.change(hour: 20)) }
    let!(:rule) do
      create(:scheduling_rule, :weekday, organization: organization, person: person,
                                         house_role: bar_role, day_of_week: 4)
    end

    before { staff!(person, bar_role) }

    context "in unavailable mode (marks are days off)" do
      it "flags a match covered by an all-day mark, but leaves it selectable" do
        create(:staff_unavailability, person: person, date: thursday)

        match = matcher.matches.first
        expect(match.unavailable).to be(true)
        expect(match).to be_selectable
        expect(match).not_to be_prechecked
      end

      it "doesn't flag when the mark covers the other day part" do
        create(:staff_unavailability, :afternoon, person: person, date: thursday)

        expect(matcher.matches.first.unavailable).to be(false)
      end

      it "flags an evening shift blocked by an evening mark" do
        create(:staff_unavailability, :evening, person: person, date: thursday)

        expect(matcher.matches.first.unavailable).to be(true)
      end
    end

    context "in available mode (marks are the only workable days)" do
      before { person.update!(availability_mode: "available") }

      it "flags an unmarked day as unavailable" do
        expect(matcher.matches.first.unavailable).to be(true)
      end

      it "doesn't flag a day they marked as workable" do
        create(:staff_unavailability, person: person, date: thursday)

        expect(matcher.matches.first.unavailable).to be(false)
      end
    end
  end

  describe "existing shifts and assignments" do
    let(:person) { create(:person, name: "Haley") }
    let!(:show) { create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20), duration_minutes: 90) }
    let!(:rule) do
      create(:scheduling_rule, organization: organization, person: person,
                               house_role: tech_role, production: production)
    end

    before { staff!(person, tech_role) }

    it "finds the shift already anchored to the show" do
      shift = create(:shift, organization: organization, house_role: tech_role, source: show,
                             starts_at: show.date_and_time, ends_at: show.ends_at)

      match = matcher.matches.first
      expect(match.existing_shift).to eq(shift)
      expect(match.already_assigned).to be(false)
      expect(match).to be_prechecked
    end

    it "marks the match already-assigned when the person is on the shift" do
      shift = create(:shift, organization: organization, house_role: tech_role, source: show,
                             starts_at: show.date_and_time, ends_at: show.ends_at)
      create(:shift_assignment, shift: shift, person: person)

      match = matcher.matches.first
      expect(match.already_assigned).to be(true)
      expect(match).not_to be_selectable
    end

    it "counts an overlapping same-role shift the person is on as already-assigned" do
      other = create(:shift, organization: organization, house_role: tech_role,
                             starts_at: show.date_and_time - 1.hour, ends_at: show.ends_at + 1.hour)
      create(:shift_assignment, shift: other, person: person)

      expect(matcher.matches.first.already_assigned).to be(true)
    end
  end

  describe "staffing status" do
    let!(:show) { create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20)) }

    it "produces no rows for someone no longer on staff" do
      person = create(:person)
      member = staff!(person, tech_role)
      create(:scheduling_rule, organization: organization, person: person,
                               house_role: tech_role, production: production)
      member.update!(archived_at: Time.current)

      expect(matcher.matches).to be_empty
    end

    it "flags someone on staff but not qualified for the role" do
      person = create(:person)
      staff!(person, bar_role) # on staff, but not tech-qualified
      create(:scheduling_rule, organization: organization, person: person,
                               house_role: tech_role, production: production)

      match = matcher.matches.first
      expect(match.qualified).to be(false)
      expect(match).not_to be_selectable
    end
  end

  describe "#find" do
    it "returns only matches whose keys are asked for, ignoring unknown keys" do
      person = create(:person)
      staff!(person, tech_role)
      create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20))
      create(:scheduling_rule, organization: organization, person: person,
                               house_role: tech_role, production: production)

      m = matcher
      key = m.matches.first.key
      expect(m.find([ key, "999:2020-01-01:0" ]).map(&:key)).to eq([ key ])
    end
  end
end
