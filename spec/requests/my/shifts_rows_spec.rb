# frozen_string_literal: true

require "rails_helper"

# My Shifts on a phone (Tim, 2026-11-07): one shift, two lines, grouped by
# week; tapping a row opens its sheet with the shows, who else is on (only
# people who've been told) and "I can't make it"; a notice's link lands on
# the row by its anchor.
RSpec.describe "My::Shifts rows and sheet", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Dana Morris") }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:membership) { create(:organization_staff_member, organization: org, person: person) }
  let!(:bar) { create(:house_role, organization: org, name: "Bar") }
  let!(:door) { create(:house_role, organization: org, name: "Door") }
  let(:week_start) { Date.current.beginning_of_week + 7 }
  let(:friday) { (week_start + 4).in_time_zone.change(hour: 19) }
  let!(:shift) { create(:shift, organization: org, house_role: bar, starts_at: friday, ends_at: friday + 4.hours, notes: "Keys are in the office drawer.") }
  let!(:assignment) { shift.shift_assignments.create!(person: person, position: 1, notified_at: 1.day.ago) }
  let!(:next_week_shift) { create(:shift, organization: org, house_role: door, starts_at: friday + 7.days, ends_at: friday + 7.days + 3.hours) }
  let!(:next_week_row) { next_week_shift.shift_assignments.create!(person: person, position: 1, notified_at: 1.day.ago) }
  let(:door_shift) { create(:shift, organization: org, house_role: door, starts_at: friday + 1.hour, ends_at: friday + 3.hours) }
  let(:told) { create(:person, name: "Mia Manager", user: create(:user)) }
  let(:untold) { create(:person, name: "Uma Untold", user: create(:user)) }

  before do
    org.people << person
    [ week_start, week_start + 7 ].each { |ws| StaffingFinalization.create!(organization: org, week_start: ws, finalized_at: Time.current) }
    door_shift.shift_assignments.create!(person: told, position: 1, notified_at: 1.day.ago)
    door_shift.shift_assignments.create!(person: untold, position: 2)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "lists one shift per row with an anchor, grouped by week, the row opening its sheet" do
    get my_shifts_path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    section = doc.at_css("[data-controller='shift-landing']")
    expect(section).to be_present
    expect(section.text).to include("Next week", "Week of #{(week_start + 7).strftime('%b %-d')}")

    row = section.at_css("#shift-#{shift.id}")
    expect(row["data-shift-row"]).to eq("on")
    expect(row["data-modal-id"]).to eq("cant-make-it-#{assignment.id}")
    expect(row.text.squish).to include("Bar · 7:00–11:00 PM")
    expect(row.text).not_to include("Stars & Garters") # one organization: named once, in the heading
    expect(section.at_css("#shift-#{next_week_shift.id}")).to be_present

    sheet = doc.at_css("#cant-make-it-#{assignment.id}[data-sheet]")
    expect(sheet.text).to include("Bar", "7:00–11:00 PM", "Also on", "Mia Manager (Door)", "Keys are in the office drawer.", "Can't make this shift?")
    expect(sheet.text).not_to include("Uma Untold")
    expect(sheet.at_css("button[type='submit'][form='decline-shift-#{assignment.id}']")).to be_present
  end

  it "keeps the row's buttons for a shift they can't make, and no sheet" do
    assignment.decline!(reason: "Out of town")
    get my_shifts_path
    row = Nokogiri::HTML(response.body).at_css("#shift-#{shift.id}")
    expect(row["data-shift-row"]).to eq("dropped")
    expect(row["data-modal-id"]).to be_nil
    expect(row.text).to include("You told them you can't make it", "Out of town", "I'm back on")
  end
end
