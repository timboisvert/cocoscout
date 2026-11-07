# frozen_string_literal: true

require "rails_helper"

# When "no longer scheduled" is owed (plan: staffing notifications §4): a
# person taken off a shift of a published week, told or not (My Shifts shows
# every row of a published week), a deleted shift, and a told shift moved to
# another week. Never for a draft week, never for someone who said they
# can't make it.
RSpec.describe "Manage::Staffing shift removals", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:bar) { create(:house_role, organization: org, name: "Bar") }
  let(:week_start) { Date.current.beginning_of_week + 7 }
  let(:shift_at) { (week_start + 4).in_time_zone.change(hour: 18) }
  let!(:shift) { create(:shift, organization: org, house_role: bar, required_count: 2, starts_at: shift_at, ends_at: shift_at + 5.hours) }
  let(:jamie) { create(:person, name: "Jamie Cruz", user: create(:user)) }
  let!(:row) { shift.shift_assignments.create!(person: jamie, position: 1) }

  before do
    org.people << jamie
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def removals = org.staff_schedule_removals.order(:id)

  it "records nothing for a draft week nobody was told about" do
    delete manage_unassign_staffing_shift_path(shift, person_id: jamie.id)
    expect(removals).to be_empty
  end

  it "records a removal, with the hours, for a shift seen on a published week before any notice" do
    create(:staffing_finalization, organization: org, week_start: week_start, finalized_at: Time.current)
    delete manage_unassign_staffing_shift_path(shift, person_id: jamie.id)
    removal = removals.last
    expect(removal).to have_attributes(person_id: jamie.id, shift_label: "Bar", shift_starts_at: shift.starts_at, shift_ends_at: shift.ends_at)
    expect(removal.hours).to eq("6:00–11:00 PM")
  end

  it "records one for everyone told when the shift is deleted, with what they were told" do
    row.update!(StaffScheduleNotices.told_attributes(shift))
    shift.update!(starts_at: shift_at + 1.hour)
    delete manage_destroy_staffing_shift_path(shift)
    expect(removals.last.shift_starts_at).to eq(shift_at)
  end

  it "records nothing for someone who said they can't make it" do
    row.update!(StaffScheduleNotices.told_attributes(shift))
    row.decline!
    delete manage_unassign_staffing_shift_path(shift, person_id: jamie.id)
    expect(removals).to be_empty
  end

  it "treats a told shift moved to another week as no longer scheduled there, and new where it lands" do
    row.update!(StaffScheduleNotices.told_attributes(shift))
    patch manage_update_staffing_shift_path(shift), params: { shift: { starts_at: (shift_at + 7.days).iso8601, ends_at: (shift_at + 7.days + 5.hours).iso8601 } }
    expect(response).to have_http_status(:redirect)
    expect(removals.last).to have_attributes(person_id: jamie.id, shift_starts_at: shift_at, shift_label: "Bar")
    expect(row.reload.notified_at).to be_nil
    expect(row.told_starts_at).to be_nil

    plan = StaffScheduleNotices.new(org, week_start, org.shifts.for_week(week_start).to_a).plan
    expect(plan[:update].map { |u| u[:reason] }).to eq([ :removed ])
    next_plan = StaffScheduleNotices.new(org, week_start + 7, org.shifts.for_week(week_start + 7).to_a).plan
    expect(next_plan[:update].map { |u| u[:reason] }).to eq([ :new ])
  end

  it "keeps a same-week time change as a change, not a removal" do
    row.update!(StaffScheduleNotices.told_attributes(shift))
    patch manage_update_staffing_shift_path(shift), params: { shift: { starts_at: (shift_at + 1.hour).iso8601, ends_at: (shift_at + 6.hours).iso8601 } }
    expect(removals).to be_empty
    expect(row.reload.notified_at).to be_present
    expect(StaffScheduleNotices.changed?(row.reload)).to be(true)
  end
end
