# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::TimeEntries", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let!(:org) { create(:organization) }
  let!(:membership) { create(:organization_staff_member, organization: org, person: person) }
  let!(:role) { create(:house_role, organization: org) }
  let!(:shift) do
    create(:shift, organization: org, house_role: role,
                   starts_at: 2.days.ago.change(hour: 18), ends_at: 2.days.ago.change(hour: 23))
  end
  let!(:assignment) { create(:shift_assignment, shift: shift, person: person) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "confirms a scheduled shift into a time entry with computed hours" do
    expect {
      post my_time_entries_path, params: {
        shift_assignment_id: assignment.id,
        started_at: shift.starts_at.strftime("%Y-%m-%dT%H:%M"),
        ended_at: shift.ends_at.strftime("%Y-%m-%dT%H:%M")
      }
    }.to change(StaffTimeEntry, :count).by(1)

    entry = StaffTimeEntry.last
    expect(entry.source).to eq("shift")
    expect(entry.shift_assignment).to eq(assignment)
    expect(entry.person).to eq(person)
    expect(entry.organization).to eq(org)
    expect(entry.hours).to eq(5.0)
    expect(entry).not_to be_paid
  end

  it "confirming the same shift twice updates instead of duplicating" do
    post my_time_entries_path, params: { shift_assignment_id: assignment.id,
                                         started_at: shift.starts_at.strftime("%Y-%m-%dT%H:%M"),
                                         ended_at: shift.ends_at.strftime("%Y-%m-%dT%H:%M") }
    expect {
      post my_time_entries_path, params: { shift_assignment_id: assignment.id,
                                           started_at: shift.starts_at.strftime("%Y-%m-%dT%H:%M"),
                                           ended_at: (shift.ends_at + 30.minutes).strftime("%Y-%m-%dT%H:%M") }
    }.not_to change(StaffTimeEntry, :count)
    expect(StaffTimeEntry.last.hours).to eq(5.5)
  end

  it "logs ad-hoc time tied to an org the worker staffs" do
    expect {
      post my_time_entries_path, params: {
        organization_id: org.id,
        started_at: 1.day.ago.change(hour: 13).strftime("%Y-%m-%dT%H:%M"),
        ended_at: 1.day.ago.change(hour: 16).strftime("%Y-%m-%dT%H:%M"),
        notes: "Came in to restock"
      }
    }.to change(StaffTimeEntry, :count).by(1)
    expect(StaffTimeEntry.last.source).to eq("manual")
    expect(StaffTimeEntry.last.hours).to eq(3.0)
  end

  it "won't let a worker edit a paid entry" do
    entry = create(:staff_time_entry, :paid, organization: org, person: person)
    patch my_time_entry_path(entry), params: { notes: "sneaky" }
    expect(response).to have_http_status(:not_found).or redirect_to(my_shifts_path)
  end

  describe "hours carry a role (the role prices the work)" do
    it "stamps a shift confirmation with the shift's role" do
      post my_time_entries_path, params: {
        shift_assignment_id: assignment.id,
        started_at: shift.starts_at.strftime("%Y-%m-%dT%H:%M"),
        ended_at: shift.ends_at.strftime("%Y-%m-%dT%H:%M")
      }
      expect(StaffTimeEntry.last.house_role).to eq(role)
    end

    it "saves the chosen role on self-logged time" do
      post my_time_entries_path, params: {
        organization_id: org.id, house_role_id: role.id,
        started_at: 1.day.ago.change(hour: 13).strftime("%Y-%m-%dT%H:%M"),
        ended_at: 1.day.ago.change(hour: 16).strftime("%Y-%m-%dT%H:%M")
      }
      entry = StaffTimeEntry.last
      expect(entry.source).to eq("manual")
      expect(entry.house_role).to eq(role)
    end

    it "rejects self-logged time with no role when the person has roles to pick from" do
      create(:staff_role_qualification, organization_staff_member: membership, house_role: role)
      expect {
        post my_time_entries_path, params: {
          organization_id: org.id,
          started_at: 1.day.ago.change(hour: 13).strftime("%Y-%m-%dT%H:%M"),
          ended_at: 1.day.ago.change(hour: 16).strftime("%Y-%m-%dT%H:%M")
        }
      }.not_to change(StaffTimeEntry, :count)
      expect(flash[:alert]).to include("Pick the role")
    end

    it "still allows role-less time when the person has no qualified roles (default rate applies)" do
      expect {
        post my_time_entries_path, params: {
          organization_id: org.id,
          started_at: 1.day.ago.change(hour: 13).strftime("%Y-%m-%dT%H:%M"),
          ended_at: 1.day.ago.change(hour: 16).strftime("%Y-%m-%dT%H:%M")
        }
      }.to change(StaffTimeEntry, :count).by(1)
      expect(StaffTimeEntry.last.house_role).to be_nil
    end

    it "rejects a role from another organization" do
      foreign_role = create(:house_role)
      post my_time_entries_path, params: {
        organization_id: org.id, house_role_id: foreign_role.id,
        started_at: 1.day.ago.change(hour: 13).strftime("%Y-%m-%dT%H:%M"),
        ended_at: 1.day.ago.change(hour: 16).strftime("%Y-%m-%dT%H:%M")
      }
      expect(StaffTimeEntry.where(house_role: foreign_role)).to be_empty
    end
  end
end
