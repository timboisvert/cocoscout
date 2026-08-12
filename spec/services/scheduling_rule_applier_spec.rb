# frozen_string_literal: true

require "rails_helper"

RSpec.describe SchedulingRuleApplier do
  let(:organization) { create(:organization, :pro) }
  let(:production) { create(:production, organization: organization) }
  let(:week_start) { Date.current.beginning_of_week + 1.week }
  let(:tuesday) { week_start + 1 }

  let(:tech_role) { create(:house_role, organization: organization, name: "Tech", role_type: :show_specific) }
  let(:bar_role)  { create(:house_role, organization: organization, name: "Bartender", role_type: :house, default_required_count: 2) }

  let!(:show) { create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20), duration_minutes: 90) }

  def staff!(person, *roles)
    member = OrganizationStaffMember.find_or_create_by!(organization: organization, person: person)
    roles.each { |r| create(:staff_role_qualification, organization_staff_member: member, house_role: r) }
    member
  end

  def all_keys
    SchedulingRuleMatcher.new(organization: organization, week_start: week_start).matches.map(&:key)
  end

  def apply!(keys = all_keys)
    described_class.new(organization: organization, week_start: week_start, match_keys: keys).apply!
  end

  it "creates the shift anchored to the show and assigns the person" do
    person = create(:person)
    staff!(person, tech_role)
    create(:scheduling_rule, organization: organization, person: person,
                             house_role: tech_role, production: production)

    result = apply!

    expect(result.shifts_created).to eq(1)
    expect(result.people_assigned).to eq(1)
    shift = organization.shifts.sole
    expect(shift.source).to eq(show)
    expect(shift.starts_at).to eq(show.date_and_time)
    expect(shift.ends_at).to eq(show.ends_at)
    expect(shift.assigned_people).to eq([ person ])
  end

  it "uses the role's default required count on created shifts" do
    person = create(:person)
    staff!(person, bar_role)
    create(:scheduling_rule, organization: organization, person: person,
                             house_role: bar_role, production: production)

    apply!
    expect(organization.shifts.sole.required_count).to eq(2)
  end

  it "assigns onto an existing shift instead of duplicating it" do
    existing = create(:shift, organization: organization, house_role: tech_role, source: show,
                              starts_at: show.date_and_time, ends_at: show.ends_at)
    person = create(:person)
    staff!(person, tech_role)
    create(:scheduling_rule, organization: organization, person: person,
                             house_role: tech_role, production: production)

    result = apply!

    expect(result.shifts_created).to eq(0)
    expect(organization.shifts.count).to eq(1)
    expect(existing.reload.assigned_people).to eq([ person ])
  end

  it "shares one shift between two rules for the same slot" do
    alice = create(:person, name: "Alice")
    bob = create(:person, name: "Bob")
    staff!(alice, bar_role)
    staff!(bob, bar_role)
    [ alice, bob ].each do |p|
      create(:scheduling_rule, organization: organization, person: p,
                               house_role: bar_role, production: production)
    end

    result = apply!

    expect(result.shifts_created).to eq(1)
    expect(result.people_assigned).to eq(2)
    shift = organization.shifts.sole
    expect(shift.assigned_people).to contain_exactly(alice, bob)
    expect(shift.shift_assignments.map(&:position)).to contain_exactly(1, 2)
  end

  it "applies unavailable-but-checked matches (the manager's override)" do
    person = create(:person)
    staff!(person, tech_role)
    create(:staff_unavailability, person: person, date: tuesday)
    create(:scheduling_rule, organization: organization, person: person,
                             house_role: tech_role, production: production)

    expect(apply!.people_assigned).to eq(1)
  end

  it "hard-skips already-assigned and unqualified matches even when submitted" do
    scheduled = create(:person, name: "Scheduled")
    unqualified = create(:person, name: "Unqualified")
    staff!(scheduled, tech_role)
    staff!(unqualified, bar_role)
    shift = create(:shift, organization: organization, house_role: tech_role, source: show,
                           starts_at: show.date_and_time, ends_at: show.ends_at)
    create(:shift_assignment, shift: shift, person: scheduled)
    create(:scheduling_rule, organization: organization, person: scheduled,
                             house_role: tech_role, production: production)
    create(:scheduling_rule, organization: organization, person: unqualified,
                             house_role: tech_role, production: production)

    result = apply!

    expect(result.people_assigned).to eq(0)
    expect(result.skipped).to eq(2)
    expect(shift.reload.assigned_people).to eq([ scheduled ])
    expect(organization.shifts.count).to eq(1)
  end

  it "quietly ignores unknown or stale keys" do
    result = apply!([ "999:2020-01-01:0", "garbage" ])

    expect(result.shifts_created).to eq(0)
    expect(result.people_assigned).to eq(0)
    expect(organization.shifts.count).to eq(0)
  end

  it "only applies the keys it was given" do
    person = create(:person)
    staff!(person, tech_role)
    second_show = create(:show, production: production, date_and_time: (tuesday + 2).in_time_zone.change(hour: 20))
    create(:scheduling_rule, organization: organization, person: person,
                             house_role: tech_role, production: production)

    chosen = all_keys.find { |k| k.end_with?(":#{show.id}") }
    result = apply!([ chosen ])

    expect(result.people_assigned).to eq(1)
    expect(organization.shifts.sole.source).to eq(show)
    expect(organization.shifts.where(source: second_show)).to be_empty
  end
end
