# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing shift assignment guards", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let(:foh) { create(:house_role, organization: org, name: "FOH") }
  let(:bar) { create(:house_role, organization: org, name: "Bar") }

  let(:staffer) { create(:person, name: "Quinn Qualified") }
  let!(:membership) { create(:organization_staff_member, organization: org, person: staffer) }

  let!(:shift) do
    create(:shift, organization: org, house_role: foh,
                   starts_at: 1.week.from_now.change(hour: 18), ends_at: 1.week.from_now.change(hour: 22))
  end

  before do
    org.people << staffer
    membership.house_roles << foh # qualified for FOH only
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "assigns a qualified staff member" do
    expect {
      post manage_assign_staffing_shift_path(shift), params: { person_id: staffer.id }
    }.to change(ShiftAssignment, :count).by(1)
    expect(shift.reload.assigned_people).to include(staffer)
  end

  it "rejects a staffer not qualified for the shift's role" do
    bar_shift = create(:shift, organization: org, house_role: bar,
                               starts_at: 1.week.from_now.change(hour: 18), ends_at: 1.week.from_now.change(hour: 22))
    expect {
      post manage_assign_staffing_shift_path(bar_shift), params: { person_id: staffer.id }
    }.not_to change(ShiftAssignment, :count)
  end

  it "rejects a person who isn't on staff" do
    rando = create(:person)
    org.people << rando
    expect {
      post manage_assign_staffing_shift_path(shift), params: { person_id: rando.id }
    }.not_to change(ShiftAssignment, :count)
  end

  it "won't assign to another organization's shift" do
    other_org = create(:organization)
    other_shift = create(:shift, organization: other_org,
                                 house_role: create(:house_role, organization: other_org))
    expect {
      post manage_assign_staffing_shift_path(other_shift), params: { person_id: staffer.id }
    }.not_to change(ShiftAssignment, :count)
  end

  it "unassigns a staffer from a shift" do
    create(:shift_assignment, shift: shift, person: staffer)
    expect {
      delete manage_unassign_staffing_shift_path(shift, person_id: staffer.id)
    }.to change(ShiftAssignment, :count).by(-1)
  end
end
