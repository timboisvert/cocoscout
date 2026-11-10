# frozen_string_literal: true

require "rails_helper"

# Scheduling on a phone (Design B, approved 2026-10-24): one day at a time
# with a centered day strip, the day's roles on a timeline, its shows below,
# assigning through the shared People Picker, and Publish or Notify updates
# pinned to the bottom.
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

  def day_page(day)
    get manage_staffing_scheduling_path(day: day.iso8601)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  it "works one day at a time, the chosen day in the middle of the strip, across weeks" do
    doc = day_page(week_start)
    strip = doc.at_css("[data-day-strip]")
    days = strip.css("a[data-strip-day]").map { |a| a["data-strip-day"] }
    expect(days).to eq(((week_start - 3)..(week_start + 3)).map(&:iso8601))
    expect(strip.css("a[data-strip-day]")[3]["aria-current"]).to eq("date")
    expect(strip.at_css("a[data-strip-day='#{tuesday.iso8601}']")["href"])
      .to eq(manage_staffing_scheduling_path(day: tuesday.iso8601))
    expect(strip.at_css("a[data-strip-day='#{tuesday.iso8601}'] .bg-pink-500")).to be_present # a show
    expect(doc.at_css("[data-phone-day]")["data-phone-day"]).to eq(week_start.iso8601)
    expect(doc.at_css("[data-phone-day-title]").text).to include(week_start.strftime("%A, %b %-d"))
    expect(doc.at_css("[data-phone-day]").text).not_to match(/week/i)
  end

  it "shows the day's roles on a timeline whose bars open the shift's menu, and the shows below" do
    doc = day_page(friday)
    day = doc.at_css("[data-phone-day]")
    bar = day.at_css("[data-action='click->shift-menu#open']")
    expect(bar["data-shift-menu-id-param"]).to eq("shift-menu-#{open_shift.id}")
    expect(doc.at_css("#shift-menu-#{open_shift.id}").text).to include("Add a person", "Edit time and covers", "Remove shift")
    expect(day.text).to include("1 open")

    doc = day_page(tuesday)
    expect(doc.at_css("[data-shows-today]").text).to include(production.name)
    expect(doc.at_css("[data-shows-today] [data-modal-id='show-detail-#{tuesday_show.id}']")).to be_present
  end

  it "swipes to the next and previous day, and the day's name opens a calendar of any date" do
    doc = day_page(friday)
    day = doc.at_css("[data-phone-day]")
    expect(day["data-controller"]).to eq("day-swipe")
    expect(day["data-day-swipe-next-url-value"]).to eq(manage_staffing_scheduling_path(day: (friday + 1).iso8601))
    expect(day["data-day-swipe-prev-url-value"]).to eq(manage_staffing_scheduling_path(day: (friday - 1).iso8601))
    expect(doc.at_css("[data-phone-day-title]")["data-modal-id"]).to eq("scheduling-jump")
    jump = doc.at_css("#scheduling-jump")
    expect(jump.text).to include("Pick a day", "Today")
    expect(jump.at_css("a[data-jump-day='#{tuesday.iso8601}'] .bg-pink-500")).to be_present
  end

  it "loads a tapped day into the layout's page frame, so the strip stays put and the page doesn't reload" do
    doc = day_page(friday)
    frame = doc.at_css("turbo-frame#page")
    expect(frame["target"]).to eq("_top")
    expect(frame["data-controller"]).to eq("page-frame")
    expect(frame.at_css("[data-phone-day]")).to be_present
    expect(frame.at_css("[data-controller~='shift-assign']")).to be_present # the week's payloads swap too
    link = frame.at_css("#scheduling-jump-strip a[data-strip-day='#{tuesday.iso8601}']")
    expect(link["data-action"]).to eq("page-frame#pick")
    expect(link["data-day-on"]).to eq("bg-pink-500 text-white")
    expect(link["data-label"]).to eq(tuesday.strftime("%A, %b %-d"))

    get manage_staffing_scheduling_path(day: tuesday.iso8601), headers: { "Turbo-Frame" => "page" }
    expect(response).to have_http_status(:ok)
    frame = Nokogiri::HTML(response.body).at_css("turbo-frame#page")
    expect(frame.at_css("[data-phone-day]")["data-phone-day"]).to eq(tuesday.iso8601)
    expect(frame.at_css("#scheduling-jump-strip [aria-current='date']")["data-strip-day"]).to eq(tuesday.iso8601)
  end

  it "keeps the by-role and by-person timelines on desktop, a day at a time (1 day)" do
    doc = page
    expect(doc.at_css("[data-day-view-link='#{friday.iso8601}']")["href"]).to eq(manage_staffing_scheduling_path(days: 1, day: friday.iso8601))
    expect(doc.at_css("#day-timeline-#{friday.iso8601}")).to be_nil
    expect(response.body).not_to include("Swipe to see all")

    get manage_staffing_scheduling_path(days: 1, day: friday.iso8601)
    day = Nokogiri::HTML(response.body).at_css("[data-desktop-day='#{friday.iso8601}']")
    expect(day.css("[data-day-view-target='toggle']").map(&:text).map(&:strip)).to eq([ "By role", "By person" ])
  end

  it "assigns through the shared People Picker, with the Everyone / Can work / Free filters" do
    doc = page
    picker = doc.at_css("[data-people-picker='shift-picker']")
    expect(JSON.parse(picker["data-people-picker-params-value"])).to include("scope" => "staff")
    expect(picker["data-action"]).to include("people-picker:pick->shift-assign#picked")
    expect(picker.css("[data-people-picker-target='filter']").map { |b| [ b.text, b["data-filter"] ] })
      .to eq([ [ "Everyone", "all" ], [ "Can work", "can_work" ], [ "Available the whole shift", "free" ] ])
    expect(doc.at_css("[data-shift-assign-target='form'] input[name='person_id']")).to be_present
    expect(doc.at_css("[data-shift-assign-sheet]")).to be_nil
  end

  # The day's work was half a screen down, under four rows of buttons and
  # pills (Tim, 2026-11-09). A phone now has an Actions box as Home does, a ⋯
  # beside the day's name, and the bottom bar.
  it "keeps desktop's status row off a phone, and shows the pages around Scheduling as section tiles" do
    doc = page
    expect(doc.at_css("[data-status-bar]")["class"]).to include("max-sm:hidden")
    tiles = doc.at_css("[data-phone-scheduling-links]")
    expect(tiles["class"]).to include("sm:hidden")
    expect(tiles.css("[data-section-tiles] a").map { |a| a.text.squish }).to eq(%w[Availability Roles])
    expect(doc.at_css("[data-scheduling-phone-bar]").text).to include("Draft")
    # Nothing waiting: no lines above the calendar.
    expect(doc.at_css("[data-scheduling-actions]")).to be_nil
  end

  it "says who can't make it in one line above the calendar, in the shape of Home's Actions" do
    person = create(:person, name: "Haley", user: create(:user))
    org.people << person
    assignment = open_shift.shift_assignments.create!(person: person)
    post manage_finalize_staffing_path(week_start: week_start.to_s)
    assignment.decline!(reason: "Out of town")

    doc = day_page(friday)
    box = doc.at_css("[data-phone-day] [data-scheduling-actions]")
    # Home's "Actions" heading, but no "Staff" topic: the page is already Scheduling.
    expect(box.at_css("h2").text.squish).to eq("Actions")
    row = box.at_css("[data-status='declined']")
    expect(row.text.squish).to eq("1 person can't make it")
    expect(row["data-modal-id"]).to eq("scheduling-declined")
    # Above the calendar.
    html = doc.at_css("[data-phone-day]").to_html
    expect(html.index("data-scheduling-actions")).to be < html.index("data-day-strip")
  end

  it "says how staffed the day is, and never counts the shows listed right under it" do
    summary = day_page(friday).at_css("[data-phone-day] [data-day-summary]")
    expect(summary.text.squish).to match(/\AStaffed \d+ of \d+/)
    expect(summary.text).not_to match(/\d+ shows?/)
    # A day with a show and no shifts has nothing to count, so no bar at all.
    expect(day_page(tuesday).at_css("[data-phone-day] [data-day-summary]")).to be_nil
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
