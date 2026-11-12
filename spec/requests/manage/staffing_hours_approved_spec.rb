# frozen_string_literal: true

require "rails_helper"

# "Hours approved" (plan: staffing notifications §2): approving a person's
# queue, or everyone's, tells each person what was approved and what it comes
# to; what's next is said as it is (the next payout run, named when it's
# scheduled; a bank to add when there is none). Re-approving a corrected
# entry tells them again; hours paid outside CocoScout get nothing.
RSpec.describe "Manage::Staffing hours approved", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars & Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:bar) { create(:house_role, organization: org, name: "Bartender") }
  let(:ada) { create(:person, name: "Ada Hours", user: create(:user)) }
  let(:bob) { create(:person, name: "Bob Nologin") }
  let!(:member) { create(:organization_staff_member, organization: org, person: ada, hourly_rate_cents: 2000) }
  let!(:bob_member) { create(:organization_staff_member, organization: org, person: bob, hourly_rate_cents: 2000) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def entry(person, hours:, at: Time.zone.local(2026, 11, 6, 18, 0))
    create(:staff_time_entry, organization: org, person: person, house_role: bar, hours: hours, started_at: at, ended_at: at + hours.hours)
  end

  def notifications(person) = Notification.where(user: person.user).order(:id)

  it "tells each person what was approved, with the amount, and what's next" do
    entry(ada, hours: 5.5)
    entry(ada, hours: 2, at: Time.zone.local(2026, 11, 7, 12, 0))
    entry(bob, hours: 1)

    # A notification only: no email goes (Tim, 2026-11-09).
    expect { patch manage_approve_staffing_timesheets_path, params: { all: true } }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
    expect(response).to redirect_to(manage_staffing_timesheets_path)
    expect(org.staff_time_entries.pending).to be_empty

    n = notifications(ada).last
    expect(n.kind).to eq("staff_hours_approved")
    expect(n.title).to eq("Stars & Garters approved 7.5 hours · $150.00")
    expect(n.body).to include("Fri, Nov 6", "Bartender", "5.5 hours", "$110.00", "Sat, Nov 7", "2 hours", "$40.00")
    expect(n.body).to include("It goes out with Stars & Garters's next payout run; add your bank on My Payments so it can reach you.")
    # A tap opens the notice's own words (the list), not My Payments, which says none of it.
    expect(n.path).to be_nil
    post handle_signin_path, params: { email_address: ada.user.email_address, password: password }
    get open_notification_path(n)
    expect(response).to redirect_to(notification_path(n))
    follow_redirect!
    expect(response.body).to include("Fri, Nov 6", "Bartender", "5.5 hours", "$110.00", "See your pay")
    expect(Notification.count).to eq(1) # Bob has no login to be told through
  end

  it "names the run when payouts are scheduled" do
    org.update!(payout_schedule: "weekly", payout_schedule_day: 5)
    entry(ada, hours: 1)
    patch manage_approve_staffing_timesheets_path, params: { person_id: ada.id }
    expect(notifications(ada).last.body).to match(/It goes out with the payout run on \w+day, \w+ \d+;/)
  end

  it "tells them again when a corrected entry is re-approved, and nothing for hours paid outside" do
    e = entry(ada, hours: 3)
    patch manage_approve_staffing_timesheets_path, params: { person_id: ada.id }
    e.update!(approved_at: nil, approved_by: nil, ended_at: e.started_at + 2.5.hours)
    patch manage_reapprove_staffing_timesheet_path(e)
    expect(notifications(ada).count).to eq(2)
    expect(notifications(ada).last.title).to eq("Stars & Garters approved 2.5 hours · $50.00")

    paid = entry(ada, hours: 1, at: Time.zone.local(2026, 11, 8, 12, 0))
    patch manage_mark_paid_offline_staffing_timesheet_path(paid), params: { note: "Check" }
    expect(notifications(ada).count).to eq(2)
  end
end
