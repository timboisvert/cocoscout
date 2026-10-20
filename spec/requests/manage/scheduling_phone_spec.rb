# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 2: Scheduling on a phone is a week strip with one day's
# shifts under it, the Gantt charts kept for desktop, the assign modal a
# sheet, and Publish or Notify updates pinned to the bottom.
RSpec.describe "Scheduling on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }

  let(:week_start) { Date.current.beginning_of_week + 1.week }
  let(:tuesday) { week_start + 1 }
  let(:friday) { week_start + 4 }
  let(:tech_role) { create(:house_role, organization: org, name: "Tech") }

  let!(:tuesday_show) { create(:show, production: production, date_and_time: tuesday.in_time_zone.change(hour: 20), duration_minutes: 90) }
  let!(:open_shift) do
    create(:shift, organization: org, house_role: tech_role,
                   starts_at: friday.in_time_zone.change(hour: 18), ends_at: friday.in_time_zone.change(hour: 22))
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def page
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  it "draws the week as a strip with a day button per day, dots for shows and open slots" do
    doc = page
    strip = doc.at_css("[data-week-strip]")
    buttons = strip.css("button[data-week-agenda-target='day']")
    expect(buttons.size).to eq(7)
    expect(buttons.map { |b| b["data-day"] }).to eq((week_start..week_start + 6).map(&:iso8601))

    tue = buttons.find { |b| b["data-day"] == tuesday.iso8601 }
    fri = buttons.find { |b| b["data-day"] == friday.iso8601 }
    mon = buttons.find { |b| b["data-day"] == week_start.iso8601 }
    expect(tue.at_css(".bg-pink-500")).to be_present     # a show
    expect(fri["data-open-slots"]).to eq("1")
    expect(fri.at_css(".bg-amber-500")).to be_present    # nobody's on the shift
    expect(mon["disabled"]).to be_present                # nothing that day
  end

  it "tags each day row so the strip can show one at a time, and swipes along the days" do
    doc = page
    rows = doc.css("[data-week-agenda-target='row']")
    expect(rows.map { |r| r["data-day"] }).to eq([ tuesday.iso8601, friday.iso8601 ])
    expect(rows.first["id"]).to eq("day-#{tuesday.iso8601}")
    expect(doc.at_css("[data-action*='week-agenda#touchEnd']")).to be_present
    expect(doc.at_css("[data-controller~='week-agenda']")).to be_present
  end

  it "keeps the Gantt toggle for desktop and drops the old swipe hint" do
    doc = page
    toggle = doc.at_css("[data-day-view-target='toggle']").parent
    expect(toggle["class"]).to include("hidden sm:flex")
    expect(response.body).not_to include("Swipe to see all")
  end

  it "makes the assign modal a sheet on a phone" do
    sheet = page.at_css("[data-shift-assign-sheet]")
    expect(sheet["class"]).to include("max-sm:rounded-b-none")
    expect(sheet.parent["class"]).to include("max-sm:items-end")
  end

  it "pins Publish to the bottom while the week is a draft" do
    bar = page.at_css("[data-scheduling-phone-bar]")
    expect(bar.text).to include("Draft", "Publish & notify")
    expect(bar.at_css("button")["data-action"]).to eq("staffing-finalize#open")
  end

  it "pins Notify updates once published with changes to send, and nothing when everyone's current" do
    person = create(:person, name: "Haley", user: create(:user))
    org.people << person
    open_shift.shift_assignments.create!(person: person)
    post manage_finalize_staffing_path(week_start: week_start.to_s)
    expect(page.at_css("[data-scheduling-phone-bar]")).to be_nil

    create(:shift, organization: org, house_role: tech_role,
                   starts_at: tuesday.in_time_zone.change(hour: 18), ends_at: tuesday.in_time_zone.change(hour: 22))
           .shift_assignments.create!(person: person)
    bar = page.at_css("[data-scheduling-phone-bar]")
    expect(bar.text).to include("1 update to send", "Notify updates")
    expect(bar.at_css("button")["data-modal-id"]).to eq("confirm-notify-updates")
  end
end
