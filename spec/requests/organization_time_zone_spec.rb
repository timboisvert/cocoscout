# frozen_string_literal: true

require "rails_helper"

# Every organization reads in its own clock (Tim, 2026-11-07): its manage
# pages parse and show times in its zone, its staff notices say its times,
# a job for its records runs in its zone, and the thread is back on the app's
# zone when the request is over. Central until an organization picks another.
RSpec.describe "Organization time zone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Shut Up Baby", time_zone: "Pacific Time (US & Canada)") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:bar) { create(:house_role, organization: org, name: "Bartender") }
  let(:jamie) { create(:person, name: "Jamie Cruz", user: create(:user)) }
  # 7 PM in Los Angeles on Friday 2026-11-13 (9 PM Central, 03:00 UTC Saturday).
  let(:seven_pacific) { Time.find_zone("Pacific Time (US & Canada)").local(2026, 11, 13, 19, 0) }

  before do
    org.people << jamie
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "is Central until picked, and must be a real zone" do
    expect(create(:organization).time_zone).to eq("Central Time (US & Canada)")
    expect(build(:organization, time_zone: "Mars")).not_to be_valid
  end

  it "parses a manager's times in the organization's zone and shows them back the same" do
    week = Date.new(2026, 11, 9)
    post manage_create_staffing_shift_path, params: { week_start: week.iso8601,
      shift: { house_role_id: bar.id, starts_at: "2026-11-13T19:00", ends_at: "2026-11-13T23:00", required_count: 1 } }
    shift = org.shifts.order(:id).last
    expect(shift.starts_at).to eq(seven_pacific)
    expect(shift.starts_at.utc.hour).to eq(3)

    get manage_staffing_scheduling_path(week_start: week.iso8601)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-shift-starts-at="2026-11-13T19:00"')
    expect(response.body).not_to include('data-shift-starts-at="2026-11-13T21:00"')
    expect(Time.zone.name).to eq("Central Time (US & Canada)") # nothing left on the thread
  end

  it "words a staff notice in the organization's zone, wherever it's built" do
    shift = create(:shift, organization: org, house_role: bar, starts_at: seven_pacific, ends_at: seven_pacific + 4.hours)
    Time.use_zone("Eastern Time (US & Canada)") do
      expect(ShiftWords.shift_hours(shift)).to eq("7:00–11:00 PM")
      expect(ShiftWords.variables(shift, jamie)[:shift_day]).to eq("Friday, Nov 13")
    end
  end

  it "runs a job for the organization's records in its zone" do
    zone_seen = nil
    stub_const("ZoneProbeJob", Class.new(ApplicationJob) { define_method(:perform) { |_org| zone_seen = Time.zone.name } })
    ZoneProbeJob.perform_now(org)
    expect(zone_seen).to eq("Pacific Time (US & Canada)")
    expect(TimeZones.of(create(:shift, organization: org, house_role: bar))).to eq("Pacific Time (US & Canada)")
    expect(TimeZones.of({ organization_id: org.id })).to eq("Pacific Time (US & Canada)")
    expect(TimeZones.of("nothing", nil)).to be_nil
  end

  it "shows the viewer's shifts in each organization's clock on My Shifts" do
    shift = create(:shift, organization: org, house_role: bar, starts_at: seven_pacific, ends_at: seven_pacific + 4.hours)
    shift.shift_assignments.create!(person: jamie, position: 1, notified_at: 1.day.ago)
    create(:staffing_finalization, organization: org, week_start: Date.new(2026, 11, 9), finalized_at: Time.current)
    get signout_path
    post handle_signin_path, params: { email_address: jamie.user.email_address, password: "Password123!" }
    travel_to Time.find_zone("Central Time (US & Canada)").local(2026, 11, 10, 12, 0) do
      get my_shifts_path
      expect(response.body).to include("7:00–11:00 PM")
      expect(response.body).not_to include("9:00 PM–1:00 AM")
    end
  end

  it "saves the zone from Organization settings" do
    patch manage_organization_path(org), params: { organization: { time_zone: "Eastern Time (US & Canada)" } }
    expect(org.reload.time_zone).to eq("Eastern Time (US & Canada)")
  end
end
