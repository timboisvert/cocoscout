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
  # The hero says the weekday when the shift is within six days, else the date.
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
    production = create(:production, organization: org, name: "Rising Stars")
    show = create(:show, production: production, date_and_time: friday + 1.5.hours)
    shift.update!(source: show)
    allow(ShiftExpectedAttendance).to receive(:for).and_wrap_original do |m, shifts|
      shifts.include?(shift) ? { shift.id => [ ShiftExpectedAttendance::Line.new(show: show, expected: 12) ] } : m.call(shifts)
    end
    [ week_start, week_start + 7 ].each { |ws| StaffingFinalization.create!(organization: org, week_start: ws, finalized_at: Time.current) }
    door_shift.shift_assignments.create!(person: told, position: 1, notified_at: 1.day.ago)
    door_shift.shift_assignments.create!(person: untold, position: 2)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "puts the next shift first, then one shift per row with an anchor, grouped by week, each opening its sheet" do
    get my_shifts_path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    page = doc.at_css("[data-controller~='shift-landing']")
    expect(page).to be_present

    # The nearest shift is the hero card, carrying the shift's anchor and
    # opening the same sheet; the list is "Then 1 more".
    hero = page.at_css("[data-next-shift]")
    expect(hero["id"]).to eq("shift-#{shift.id}")
    expect(hero.text.squish).to include("Next shift Bar, 7:00–11:00 PM", "#{friday.strftime('%A, %b %-d')} · Stars & Garters")
    # The whole night on the card: each show with its time and count, and
    # everyone working alongside with role and hours (told people only).
    expect(hero.at_css("[data-next-shift-shows]").text.squish).to include("That night", "8:30 PM", "Rising Stars", "12 expected")
    crew = hero.at_css("[data-next-shift-crew]").text.squish
    expect(crew).to include("Working with you", "Mia Manager", "Door", "8:00–10:00 PM")
    expect(crew).not_to include("Uma Untold")
    expect(hero.text).to include("Keys are in the office drawer.")
    expect(hero.at_css("[data-modal-id='cant-make-it-#{assignment.id}']")).to be_present
    expect(page.at_css("[data-upcoming-shifts]").text.squish).to include("Upcoming shifts 1 more · Stars & Garters", "Week of #{(week_start + 7).strftime('%b %-d')}")
    expect(page.at_css("[data-upcoming-shifts] #shift-#{shift.id}")).to be_nil

    row = page.at_css("#shift-#{next_week_shift.id}")
    expect(row["data-shift-row"]).to eq("on")
    expect(row["data-modal-id"]).to eq("cant-make-it-#{next_week_row.id}")
    expect(row.text.squish).to include("Door · 7:00–10:00 PM")
    expect(row.text).not_to include("Stars & Garters") # one organization: named once, on the card

    sheet = doc.at_css("#cant-make-it-#{assignment.id}[data-sheet]")
    expect(sheet.text).to include("Bar", "7:00–11:00 PM", "Also on", "Mia Manager (Door)", "Keys are in the office drawer.", "Can't make this shift?")
    expect(sheet.text).not_to include("Uma Untold")
    expect(sheet.at_css("button[type='submit'][form='decline-shift-#{assignment.id}']")).to be_present
    expect(doc.at_css("#cant-make-it-#{next_week_row.id}[data-sheet]")).to be_present

    # The glance: hours to verify beside the money; the rest only on a wide screen.
    expect(doc.at_css("[data-hours-to-verify]").text).to include("Hours to verify", "all verified")
  end

  it "keeps the row's buttons for a shift they can't make, and no sheet" do
    assignment.decline!(reason: "Out of town")
    get my_shifts_path
    row = Nokogiri::HTML(response.body).at_css("#shift-#{shift.id}")
    expect(row["data-shift-row"]).to eq("dropped")
    expect(row["data-modal-id"]).to be_nil
    expect(row.text).to include("You told them you can't make it", "Out of town", "I'm back on")
    # Declined, it's no longer the next shift: the Door shift is the hero.
    expect(Nokogiri::HTML(response.body).at_css("[data-next-shift]")["id"]).to eq("shift-#{next_week_shift.id}")
  end
end
