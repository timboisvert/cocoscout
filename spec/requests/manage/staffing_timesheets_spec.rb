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

  # Pricing asks qualification_for four times per row. It used to answer with a
  # detect over the loaded association and then, on a miss, a find_by that
  # searched the same unscoped set and found the same nothing — so an entry
  # logged against a role the member isn't qualified for cost four dead queries.
  # Capping the rows must never cap the numbers above them — the summary bar and
  # the "approve everything" confirmation both describe the whole queue.
  describe "a queue longer than the page shows" do
    it "renders a capped list but counts everything" do
      limit = Manage::Staffing::TimesheetsController::PENDING_LIMIT
      other = create(:person, name: "Bob Overflow")
      create(:organization_staff_member, organization: org, person: other)
      limit.times { create(:staff_time_entry, organization: org, person: person, hours: 2) }
      3.times { create(:staff_time_entry, organization: org, person: other, hours: 1) }

      get manage_staffing_timesheets_path

      # The summary bar describes the whole queue...
      expect(response.body).to include("#{limit + 3} entries")
      expect(response.body).to include("2 people awaiting your approval")
      # ...and says plainly that the list beneath it isn't all of them.
      expect(response.body).to include("Showing the oldest #{limit}")
      # Approve-everything really does mean everything, so its count matches too.
      expect(response.body).to include("Approve every pending entry from all 2 people?")
    end
  end

  describe "the cost of the approval queue" do
    it "doesn't grow with entries priced at a role the member doesn't hold" do
      other_role = create(:house_role, organization: org, name: "Guest Spot")
      create(:staff_time_entry, organization: org, person: person, house_role: other_role)
      get manage_staffing_timesheets_path # warm
      baseline = count_queries { get manage_staffing_timesheets_path }

      5.times { create(:staff_time_entry, organization: org, person: person, house_role: other_role) }
      scaled = count_queries { get manage_staffing_timesheets_path }

      expect(scaled - baseline).to be <= 1
    end
  end

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
      # The approved calendar shows entries as "Name · Xh", so distinguish the
      # three states by person name.
      pending_person = create(:person, name: "Pending Pete")
      approved_person = create(:person, name: "Approved Ann")
      paid_person = create(:person, name: "Paid Pat")
      create(:staff_time_entry, organization: org, person: pending_person)
      create(:staff_time_entry, organization: org, person: approved_person, approved_at: Time.current, approved_by: owner)
      create(:staff_time_entry, :paid, organization: org, person: paid_person, approved_at: Time.current, approved_by: owner)

      get manage_approved_staffing_timesheets_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Approved Ann").and include("Paid Pat")
      expect(response.body).not_to include("Pending Pete")
    end

    it "shows an empty state when nothing has been approved" do
      create(:staff_time_entry, organization: org, person: person) # pending, not signed off
      get manage_approved_staffing_timesheets_path
      expect(response.body).to include("No approved hours")
    end
  end

  describe "unapprove" do
    it "sends an approved entry back to pending" do
      entry = create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner)
      patch manage_unapprove_staffing_timesheet_path(entry)
      expect(response).to redirect_to(manage_approved_staffing_timesheets_path(month: Date.current.strftime("%Y-%m")))
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

    it "offers the org's roles with this member's rates in the Adjust modal" do
      bar_role = create(:house_role, organization: org, name: "Bar Lead")
      create(:staff_role_qualification, organization_staff_member: member, house_role: bar_role, hourly_rate_cents: 2500)
      entry = create(:staff_time_entry, organization: org, person: person)

      get manage_edit_staffing_timesheet_path(entry)

      expect(response.body).to include("Adjust").and include("Worked as").and include("Bar Lead")
      expect(response.body).to include('data-rate-cents="2500"')
    end

    it "changes the role the hours were worked as (repricing them) and kicks back to review" do
      bar_role = create(:house_role, organization: org, name: "Bar Lead")
      entry = create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner)

      patch manage_staffing_timesheet_path(entry), params: {
        staff_time_entry: { started_at: "2026-07-01T18:00", ended_at: "2026-07-01T21:00", house_role_id: bar_role.id }
      }

      entry.reload
      expect(entry.house_role).to eq(bar_role)
      expect(entry.approved_at).to be_nil
    end

    it "rejects a role from another organization" do
      foreign_role = create(:house_role)
      entry = create(:staff_time_entry, organization: org, person: person)

      patch manage_staffing_timesheet_path(entry), params: {
        staff_time_entry: { started_at: "2026-07-01T18:00", ended_at: "2026-07-01T21:00", house_role_id: foreign_role.id }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(entry.reload.house_role).to be_nil
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

    # The adjust modal opens from the review queue too — approving from there
    # must land the manager back on the queue, not bounce to approved hours.
    it "returns to the page the manager was working on" do
      entry = create(:staff_time_entry, organization: org, person: person)
      patch manage_reapprove_staffing_timesheet_path(entry),
            headers: { "HTTP_REFERER" => manage_staffing_timesheets_url }
      expect(response).to redirect_to(manage_staffing_timesheets_url)
    end

    it "refuses to reapprove a paid entry" do
      entry = create(:staff_time_entry, :paid, organization: org, person: person)
      patch manage_reapprove_staffing_timesheet_path(entry)
      expect(flash[:alert]).to be_present
    end
  end
end
