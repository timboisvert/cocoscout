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

  it "keeps the by-role and by-person timelines on desktop, a day at a time" do
    doc = page
    timeline = doc.at_css("#day-timeline-#{friday.iso8601}")
    expect(timeline.css("[data-day-view-target='toggle']").map(&:text).map(&:strip)).to eq([ "By role", "By person" ])
    expect(doc.at_css("[data-modal-id='day-timeline-#{friday.iso8601}']")).to be_present
    expect(response.body).not_to include("Swipe to see all")
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
