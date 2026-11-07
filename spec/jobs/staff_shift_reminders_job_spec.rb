# frozen_string_literal: true

require "rails_helper"

# The afternoon before a shift: one reminder per person, at 4 PM on the
# organization's own clock, once per row, only for a published week, never
# for a declined row or someone without a login. Two shifts make one notice.
RSpec.describe StaffShiftRemindersJob do
  let!(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:annex) { create(:location, organization: org, name: "The Annex") }
  let!(:bar) { create(:house_role, organization: org, name: "Bartender", location: annex) }
  let!(:door) { create(:house_role, organization: org, name: "Door", location: annex) }
  let(:jamie) { create(:person, name: "Jamie Cruz", user: create(:user)) }
  let(:dan) { create(:person, name: "Dan Lee", user: create(:user)) }
  # Friday 2026-11-13 at 6 PM Central; the job runs Thursday at 4 PM.
  let(:friday) { Time.find_zone("Central Time (US & Canada)").local(2026, 11, 13, 18, 0) }
  let(:thursday_4pm) { Time.find_zone("Central Time (US & Canada)").local(2026, 11, 12, 16, 10) }

  def shift(role, at, hours: 4)
    create(:shift, organization: org, house_role: role, starts_at: at, ends_at: at + hours.hours)
  end

  def publish!(time = friday)
    create(:staffing_finalization, organization: org, week_start: time.to_date.beginning_of_week, finalized_at: Time.current)
  end

  def notifications(person) = Notification.where(user: person.user).order(:id)

  it "reminds at 4 PM the day before, once, with the shows and who else is on" do
    publish!
    production = create(:production, organization: org, name: "Rising Stars")
    show = create(:show, production: production, date_and_time: friday + 1.5.hours)
    s = shift(bar, friday)
    s.update!(source: show)
    row = s.shift_assignments.create!(person: jamie, position: 1, notified_at: 1.day.ago)
    other = shift(door, friday + 1.hour, hours: 2)
    other.shift_assignments.create!(person: dan, position: 1, notified_at: 1.day.ago)

    described_class.perform_now(thursday_4pm - 3.hours)
    expect(notifications(jamie)).to be_empty

    described_class.perform_now(thursday_4pm)
    n = notifications(jamie).last
    expect(n.kind).to eq("staff_shift_reminder")
    expect(n.title).to eq("Tomorrow: Bartender, 6:00 PM at The Annex")
    expect(n.body).to include("Friday, Nov 13", "6:00–10:00 PM", "That night: Rising Stars (7:30 PM)", "Also on: Dan Lee (Door)")
    expect(n.body).to include("so the team can sort out cover")
    expect(n.path).to eq("/my/shifts#shift-#{s.id}")
    expect(row.reload.reminded_at).to be_present

    described_class.perform_now(thursday_4pm)
    expect(notifications(jamie).count).to eq(1)
  end

  it "makes one notice of two shifts tomorrow" do
    publish!
    shift(bar, friday).shift_assignments.create!(person: jamie, position: 1, notified_at: 1.day.ago)
    shift(door, friday + 3.hours, hours: 2).shift_assignments.create!(person: jamie, position: 1, notified_at: 1.day.ago)
    described_class.perform_now(thursday_4pm)
    expect(notifications(jamie).count).to eq(1)
    expect(notifications(jamie).last.title).to eq("Tomorrow: Bartender at 6:00 PM, then Door at 9:00 PM")
  end

  it "says nothing for a draft week, a declined row, or someone without a login" do
    nolan = create(:person, name: "Nolan Nologin")
    s = shift(bar, friday)
    s.shift_assignments.create!(person: jamie, position: 1)
    s.shift_assignments.create!(person: nolan, position: 2)
    described_class.perform_now(thursday_4pm)
    expect(Notification.count).to eq(0)

    publish!
    s.shift_assignments.find_by(person: jamie).decline!
    described_class.perform_now(thursday_4pm)
    expect(Notification.count).to eq(0)
  end

  it "keeps each organization's own clock" do
    org.update!(time_zone: "Pacific Time (US & Canada)")
    publish!
    # 6 PM Central is 4 PM Pacific: the shift is "tomorrow" by the Pacific calendar too.
    shift(bar, friday).shift_assignments.create!(person: jamie, position: 1, notified_at: 1.day.ago)
    described_class.perform_now(thursday_4pm) # 2 PM in Los Angeles: not yet
    expect(notifications(jamie)).to be_empty
    described_class.perform_now(thursday_4pm + 2.hours)
    expect(notifications(jamie).last.title).to eq("Tomorrow: Bartender, 4:00 PM at The Annex")
  end
end
