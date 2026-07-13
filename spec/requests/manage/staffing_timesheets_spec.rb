# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing::Timesheets", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:person) { create(:person, name: "Ada Hours") }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2000) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "lists pending hours awaiting approval grouped by person" do
    create(:staff_time_entry, organization: org, person: person)
    get manage_staffing_timesheets_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ada Hours").and include("Approve Hours")
  end

  it "shows the all-caught-up state when nothing is pending" do
    create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner)
    get manage_staffing_timesheets_path
    expect(response.body).to include("caught up")
  end

  it "approves one person's pending hours" do
    e1 = create(:staff_time_entry, organization: org, person: person)
    e2 = create(:staff_time_entry, organization: org, person: person)

    patch manage_approve_staffing_timesheets_path(person_id: person.id)
    expect(response).to redirect_to(manage_staffing_timesheets_path)
    expect(e1.reload).to be_approved
    expect(e2.reload).to be_approved
    expect(e1.approved_by).to eq(owner)
  end

  it "approves everything with all=1" do
    other = create(:person, name: "Bo Ryan")
    create(:organization_staff_member, organization: org, person: other, hourly_rate_cents: 2000)
    a = create(:staff_time_entry, organization: org, person: person)
    b = create(:staff_time_entry, organization: org, person: other)

    patch manage_approve_staffing_timesheets_path, params: { all: "1" }
    expect(a.reload).to be_approved
    expect(b.reload).to be_approved
  end

  it "leaves already-paid entries untouched" do
    paid = create(:staff_time_entry, :paid, organization: org, person: person)
    patch manage_approve_staffing_timesheets_path(person_id: person.id)
    expect(paid.reload.approved_at).to be_nil
  end

  it "refuses to approve with no scope given" do
    patch manage_approve_staffing_timesheets_path
    expect(response).to redirect_to(manage_staffing_timesheets_path)
    expect(flash[:alert]).to be_present
  end

  describe "approved-hours history" do
    it "lists approved and paid entries, and not pending ones" do
      pending = create(:staff_time_entry, organization: org, person: person, notes: "still-pending")
      approved = create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner, notes: "signed-off")
      paid = create(:staff_time_entry, :paid, organization: org, person: person, approved_at: Time.current, approved_by: owner, notes: "paid-out")

      get manage_approved_staffing_timesheets_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("signed-off").and include("paid-out")
      expect(response.body).not_to include("still-pending")
    end

    it "shows an empty state when nothing has been approved" do
      create(:staff_time_entry, organization: org, person: person)
      get manage_approved_staffing_timesheets_path
      expect(response.body).to include("Nothing approved yet")
    end
  end

  describe "unapprove" do
    it "sends an approved entry back to pending" do
      entry = create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner)
      patch manage_unapprove_staffing_timesheet_path(entry)
      expect(response).to redirect_to(manage_approved_staffing_timesheets_path)
      entry.reload
      expect(entry.approved_at).to be_nil
      expect(entry.status).to eq("pending")
    end

    it "refuses to unapprove a paid entry" do
      entry = create(:staff_time_entry, :paid, organization: org, person: person, approved_at: Time.current, approved_by: owner)
      patch manage_unapprove_staffing_timesheet_path(entry)
      expect(flash[:alert]).to be_present
      expect(entry.reload.approved_at).to be_present
    end
  end

  describe "edit/update" do
    it "recomputes hours and kicks the entry back to review for the audit trail" do
      entry = create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner)
      patch manage_staffing_timesheet_path(entry), params: {
        staff_time_entry: {
          started_at: "2026-07-01T18:00",
          ended_at: "2026-07-01T21:30"
        }
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Re-approve now")
      entry.reload
      expect(entry.hours).to eq(3.5)
      expect(entry.approved_at).to be_nil
      expect(entry.status).to eq("pending")
    end

    it "refuses to edit a paid entry" do
      entry = create(:staff_time_entry, :paid, organization: org, person: person)
      patch manage_staffing_timesheet_path(entry), params: { staff_time_entry: { started_at: "2026-07-01T18:00", ended_at: "2026-07-01T22:00" } }
      expect(flash[:alert]).to be_present
    end
  end

  describe "reapprove" do
    it "signs off again on an edited entry" do
      entry = create(:staff_time_entry, organization: org, person: person)
      patch manage_reapprove_staffing_timesheet_path(entry)
      expect(response).to redirect_to(manage_approved_staffing_timesheets_path)
      entry.reload
      expect(entry.approved_at).to be_present
      expect(entry.approved_by).to eq(owner)
    end

    it "refuses to reapprove a paid entry" do
      entry = create(:staff_time_entry, :paid, organization: org, person: person)
      patch manage_reapprove_staffing_timesheet_path(entry)
      expect(flash[:alert]).to be_present
    end
  end
end
