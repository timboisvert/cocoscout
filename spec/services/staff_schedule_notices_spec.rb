# frozen_string_literal: true

require "rails_helper"

# One notice per thing that happened to a person (plan: staffing
# notifications, 2026-11-07): the week on first publish and Resend, a new
# shift, a changed one (against what they were told, not the row's
# timestamp), one they're no longer on with what remains that day, several
# at once with sections, off one and onto another the same day as one
# change, and nobody told a lie: a removal-only person on Resend gets the
# removal notice, people without a login are named as not told.
RSpec.describe StaffScheduleNotices do
  let!(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:annex) { create(:location, organization: org, name: "The Annex") }
  let!(:bar) { create(:house_role, organization: org, name: "Bartender", location: annex) }
  let!(:door) { create(:house_role, organization: org, name: "Door", location: annex) }
  let(:week_start) { Date.new(2026, 11, 9) }
  let(:friday) { Time.zone.local(2026, 11, 13, 18, 0) }
  let(:saturday) { Time.zone.local(2026, 11, 14, 18, 0) }

  let(:jamie) { create(:person, name: "Jamie Cruz", user: create(:user)) }
  let(:dan) { create(:person, name: "Dan Lee", user: create(:user)) }
  let(:nolan) { create(:person, name: "Nolan Nologin") }

  def shift(role, at, hours: 5.5)
    create(:shift, organization: org, house_role: role, starts_at: at, ends_at: at + hours.hours)
  end

  def told!(assignment)
    assignment.update!(StaffScheduleNotices.told_attributes(assignment.shift, at: 1.day.ago))
  end

  def week_shifts
    org.shifts.for_week(week_start).includes(:house_role, :additional_roles, :source, shift_assignments: :person).ordered.to_a
  end

  def notices
    described_class.new(org, week_start, week_shifts)
  end

  def send_updates(people = nil, everyone: false)
    n = notices
    n.send!(people: people || (everyone ? n.plan[:all_people] : n.plan[:update].map { |u| u[:person] }),
            everyone: everyone, subject: "Your work schedule — week of Nov 9", intro: "Here's what changed:")
  end

  def last_notification(person)
    Notification.where(user: person.user).order(:id).last
  end

  before { allow(ContentTemplateService).to receive(:deliver).and_call_original }

  it "sends the week on first publish, each shift linked to its row, and never promises cover" do
    friday_shift = shift(bar, friday)
    friday_shift.shift_assignments.create!(person: jamie, position: 1)
    shift(door, saturday, hours: 4).shift_assignments.create!(person: jamie, position: 1)

    expect(notices.plan[:update].map { |u| [ u[:person].name, u[:reason] ] }).to eq([ [ "Jamie Cruz", :new ] ])
    result = send_updates(everyone: true)
    expect(result[:notified]).to eq(1)

    n = last_notification(jamie)
    expect(n.kind).to eq("staff_schedule_notification")
    expect(n.title).to eq("Your shifts for the week of November 9 are set · 2 shifts")
    expect(n.body).to include("Friday, Nov 13", "6:00–11:30 PM", "Bartender", "The Annex", "Saturday, Nov 14", "Door")
    expect(n.body).to include("/my/shifts#shift-#{friday_shift.id}")
    expect(n.body).to include("so the team can sort out cover")
    expect(n.body).not_to include("we'll find cover")
    expect(n.path).to eq("/my/shifts#shift-#{friday_shift.id}")

    row = friday_shift.shift_assignments.find_by(person: jamie)
    expect(row.notified_at).to be_present
    expect(row.told_starts_at).to eq(friday_shift.starts_at)
    expect(row.told_role_label).to eq("Bartender")
    expect(row.told_location_name).to eq("The Annex")
    expect(notices.plan[:update]).to be_empty
  end

  it "says New shift, with that night's shows and only the people who've been told" do
    production = create(:production, organization: org, name: "Rising Stars")
    show = create(:show, production: production, date_and_time: friday + 1.5.hours)
    s = shift(bar, friday)
    s.update!(source: show)
    s.shift_assignments.create!(person: jamie, position: 1)
    door_shift = shift(door, friday + 2.hours, hours: 3)
    told!(door_shift.shift_assignments.create!(person: dan, position: 1))
    untold = create(:person, name: "Uma Untold", user: create(:user))
    door_shift.shift_assignments.create!(person: untold, position: 2)

    send_updates
    n = last_notification(jamie)
    expect(n.kind).to eq("staff_shift_added")
    expect(n.title).to eq("New shift: Bartender, Fri Nov 13, 6:00–11:30 PM at The Annex")
    expect(n.body).to include("That night: Rising Stars (7:30 PM)")
    expect(n.body).to include("Also on: Dan Lee (Door)")
    expect(n.body).not_to include("Uma Untold")
    expect(n.path).to eq("/my/shifts#shift-#{s.id}")
  end

  it "judges changed against what they were told, not the row's timestamp" do
    s = shift(bar, friday)
    row = s.shift_assignments.create!(person: jamie, position: 1)
    told!(row)

    # A touch with nothing visible: not a change.
    s.update!(notes: "Keys in the drawer")
    expect(notices.plan[:update]).to be_empty

    s.update!(starts_at: friday - 30.minutes, ends_at: friday + 5.hours)
    expect(notices.plan[:update].map { |u| u[:reason] }).to eq([ :changed ])
    send_updates
    n = last_notification(jamie)
    expect(n.kind).to eq("staff_shift_changed")
    expect(n.title).to eq("New time for your Bartender shift, Fri Nov 13: 5:30–11:00 PM")
    expect(n.body).to include("<s>6:00–11:30 PM</s>", "<strong>5:30–11:00 PM</strong>")
    expect(row.reload.told_starts_at).to eq(s.starts_at)
  end

  it "names a role change, a move to another day, and several changes at once" do
    s = shift(bar, friday)
    row = s.shift_assignments.create!(person: jamie, position: 1)
    told!(row)
    s.assign_additional_roles!([ door.id ])
    s.reload
    expect(notices.send(:change_title, StaffScheduleNotices::Item.new(kind: :changed, shift: s, assignment: row.reload),
                        notices.send(:change_lines, StaffScheduleNotices::Item.new(kind: :changed, shift: s, assignment: row))))
      .to eq("Your Fri Nov 13 shift is now Bartender + Door")

    told!(row.reload)
    s.update!(starts_at: saturday, ends_at: saturday + 5.5.hours)
    item = StaffScheduleNotices::Item.new(kind: :changed, shift: s.reload, assignment: row.reload)
    expect(notices.send(:change_title, item, notices.send(:change_lines, item))).to eq("Your Bartender + Door shift moved: now Sat Nov 14, 6:00 PM")

    told!(row.reload)
    s.update!(starts_at: saturday - 1.hour, ends_at: saturday + 4.hours)
    s.assign_additional_roles!([])
    item = StaffScheduleNotices::Item.new(kind: :changed, shift: s.reload, assignment: row.reload)
    expect(notices.send(:change_title, item, notices.send(:change_lines, item))).to eq("Changes to your Bartender shift, Sat Nov 14")
  end

  it "says no longer scheduled, naming the shift and what's still on that day" do
    gone = shift(bar, friday)
    gone_row = gone.shift_assignments.create!(person: jamie, position: 1)
    told!(gone_row)
    kept = shift(door, friday + 2.hours, hours: 3)
    told!(kept.shift_assignments.create!(person: jamie, position: 1))
    sat = shift(door, saturday, hours: 4)
    told!(sat.shift_assignments.create!(person: jamie, position: 1))

    StaffScheduleRemoval.record!(gone_row)
    gone_row.destroy!

    expect(notices.plan[:update].map { |u| u[:reason] }).to eq([ :removed ])
    send_updates
    n = last_notification(jamie)
    expect(n.kind).to eq("staff_shift_removed")
    expect(n.title).to eq("No longer scheduled: Bartender, Fri Nov 13, 6:00 PM. You're still on Door that night, 8:00–11:00 PM.")
    expect(n.body).to include("has come off the schedule at Stars & Garters.")
    expect(n.body).not_to include("evening back")
    expect(n.body).to include("Still on your schedule that day", "The rest of your week", "Saturday, Nov 14")
    expect(n.body).not_to include("reply to this message")
  end

  it "gives the evening back only when nothing else that day remains, and the afternoon for a matinee" do
    gone = shift(bar, friday)
    row = gone.shift_assignments.create!(person: jamie, position: 1)
    told!(row)
    StaffScheduleRemoval.record!(row)
    row.destroy!
    send_updates
    expect(last_notification(jamie).body).to include("so you have that evening back")

    matinee = shift(bar, Time.zone.local(2026, 11, 15, 13, 0), hours: 4)
    row = matinee.shift_assignments.create!(person: dan, position: 1)
    told!(row)
    StaffScheduleRemoval.record!(row)
    row.destroy!
    send_updates
    n = last_notification(dan)
    expect(n.title).to eq("No longer scheduled: Bartender, Sun Nov 15, 1:00 PM.")
    expect(n.body).to include("so you have that afternoon back")
  end

  it "records a removal for a shift seen on a published week even before any notice" do
    create(:staffing_finalization, organization: org, week_start: week_start, finalized_at: Time.current)
    s = shift(bar, friday)
    row = s.shift_assignments.create!(person: jamie, position: 1)
    expect(StaffScheduleRemoval.record!(row)).to be_present

    draft = shift(bar, friday + 7.days)
    row2 = draft.shift_assignments.create!(person: jamie, position: 1)
    expect(StaffScheduleRemoval.record!(row2)).to be_nil

    row.decline!
    expect(StaffScheduleRemoval.record!(row)).to be_nil
  end

  it "folds several changes into one notice with sections, and a same-day swap into one change" do
    gone = shift(bar, friday)
    gone_row = gone.shift_assignments.create!(person: jamie, position: 1)
    told!(gone_row)
    StaffScheduleRemoval.record!(gone_row)
    gone_row.destroy!
    instead = shift(door, friday, hours: 5)
    instead.shift_assignments.create!(person: jamie, position: 1)
    sat = shift(door, saturday, hours: 4)
    sat_row = sat.shift_assignments.create!(person: jamie, position: 1)
    told!(sat_row)
    sat.update!(starts_at: saturday - 1.hour)

    expect(notices.plan[:update].map { |u| u[:reason] }).to eq([ :changed ])
    send_updates
    n = last_notification(jamie)
    expect(n.kind).to eq("staff_schedule_changes")
    expect(n.title).to eq("2 changes to your shifts, week of November 9: 2 changed")
    expect(n.body).to include("Instead of <s>Bartender, 6:00–11:30 PM</s> → <strong>Door, 6:00–11:00 PM</strong>")
    expect(n.body).to include("<s>6:00–10:00 PM</s> → <strong>5:00–10:00 PM</strong>")
    expect(n.body).not_to include("No longer scheduled")
  end

  it "sends a removal-only person the removal notice on Resend, not a week that says confirmed" do
    gone = shift(bar, friday)
    gone_row = gone.shift_assignments.create!(person: jamie, position: 1)
    told!(gone_row)
    StaffScheduleRemoval.record!(gone_row)
    gone_row.destroy!
    told!(shift(door, saturday).shift_assignments.create!(person: dan, position: 1))

    result = send_updates(everyone: true)
    expect(result[:notified]).to eq(2)
    expect(last_notification(jamie).kind).to eq("staff_shift_removed")
    expect(last_notification(dan).kind).to eq("staff_schedule_notification")
    expect(StaffScheduleRemoval.pending.count).to eq(0)
  end

  it "names people without a login as not told, instead of calling everyone up to date" do
    shift(bar, friday).shift_assignments.create!(person: nolan, position: 1)
    plan = notices.plan
    expect(plan[:unreachable]).to eq([ nolan ])
    result = send_updates
    expect(result).to eq(notified: 0, unreachable: [ nolan ])
  end

  it "never re-sends the shift someone declined" do
    s = shift(bar, friday)
    row = s.shift_assignments.create!(person: jamie, position: 1)
    told!(row)
    row.decline!
    s.update!(ends_at: friday + 6.hours)
    expect(notices.plan[:update]).to be_empty
    expect(send_updates(everyone: true)[:notified]).to eq(0)
  end
end
