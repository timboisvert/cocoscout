# frozen_string_literal: true

require "rails_helper"

# The scheduling page answers "can they work this?" on the server, per shift,
# from the new time-band model — the whole shift, not just its start — and
# assigning says so when the answer isn't a clean yes.
RSpec.describe "Manage::Staffing availability verdicts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:foh) { create(:house_role, organization: org, name: "FOH") }

  let(:week_start) { Date.current.beginning_of_week + 1.week }
  let(:day) { week_start + 3 } # Thursday

  let(:late) { create(:person, name: "Lee Late") }
  let(:away) { create(:person, name: "Ari Away") }
  let(:open) { create(:person, name: "Oli Open") }

  let!(:shift) do
    create(:shift, organization: org, house_role: foh,
                   starts_at: Time.zone.local(day.year, day.month, day.day, 18),
                   ends_at: Time.zone.local(day.year, day.month, day.day, 23))
  end

  before do
    [ late, away, open ].each do |person|
      org.people << person
      create(:organization_staff_member, organization: org, person: person).house_roles << foh
    end
    StaffAvailabilityWriter.new(late).save_exception!(starts_on: day, ends_on: day, state: "hours",
                                                      windows: [ { from: "20:30", to: "00:00" } ])
    StaffAvailabilityWriter.new(away).save_exception!(starts_on: day - 1, ends_on: day + 2, state: "off", note: "Lisbon")
    StaffAvailabilityWriter.new(open).set_weekdays!([ day.wday ], state: "anytime")
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def payload(name)
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    raw = response.body[/data-shift-assign-#{name}-value="([^"]*)"/, 1]
    JSON.parse(CGI.unescapeHTML(raw))
  end

  it "sends a verdict per shift for everyone who isn't simply free" do
    verdicts = payload("staff-availability")

    expect(verdicts.dig(late.id.to_s, shift.id.to_s)).to include(
      "status" => "partial", "badge" => "Free from 8:30 PM",
      "detail" => "Free from 8:30 PM, misses the first 2h 30m (an exception for #{day.strftime('%b %-d')})."
    )
    expect(verdicts.dig(away.id.to_s, shift.id.to_s)).to include("status" => "blocked", "detail" => "Can't work then (“Lisbon”).")
    expect(verdicts).not_to have_key(open.id.to_s)
  end

  it "sends the hours each person can work on the days that aren't wide open" do
    windows = payload("day-windows")

    expect(windows.dig(late.id.to_s, day.iso8601)).to eq([ [ 1230, 1440 ] ])
    expect(windows.dig(away.id.to_s, day.iso8601)).to eq([])
    expect(windows).not_to have_key(open.id.to_s)
  end

  it "assigns someone partly free, and says so" do
    post manage_assign_staffing_shift_path(shift), params: { person_id: late.id }

    expect(shift.reload.assigned_people).to include(late)
    expect(flash[:notice]).to eq("Assigned Lee Late. Note: Free from 8:30 PM, misses the first 2h 30m " \
                                 "(an exception for #{day.strftime('%b %-d')}).")
  end

  it "says nothing extra for someone free" do
    post manage_assign_staffing_shift_path(shift), params: { person_id: open.id }

    expect(flash[:notice]).to eq("Assigned Oli Open.")
  end

  it "shows each person's week and exceptions in the overview" do
    get manage_staffing_scheduling_path(week_start: week_start.to_s)

    expect(response.body).to include("Lisbon")
    expect(response.body).to include("After 8:30 PM")
  end
end
