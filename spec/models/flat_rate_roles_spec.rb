# frozen_string_literal: true

require "rails_helper"

# Security comes in for the night and gets $50, whether that's three hours or
# five. Every screen that shows staffing money has to agree on that.
RSpec.describe "Flat-rate house roles", type: :model do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:person) { create(:person, name: "Sam Security") }
  let(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2_000) }

  let(:flat_role) do
    create(:house_role, organization: org, name: "Security", pay_type: "flat", default_flat_rate_cents: 5_000)
  end
  let(:hourly_role) do
    create(:house_role, organization: org, name: "Bartender", default_hourly_rate_cents: 2_000)
  end

  # Anchored at midday, not "now" — the flat-shift rule keys off the calendar
  # date, so a fixture built from Time.current silently straddles midnight when
  # the suite runs in the evening and a one-shift test becomes a two-day one.
  let(:work_day) { 2.days.ago.midday }

  def entry!(role, hours:, shift_assignment: nil)
    org.staff_time_entries.create!(person: person, house_role: role, hours: hours,
                                   started_at: work_day, ended_at: work_day + hours.hours,
                                   shift_assignment: shift_assignment,
                                   approved_at: Time.current)
  end

  describe "pricing" do
    it "pays the flat amount however many hours were worked" do
      expect(member.amount_cents_for(flat_role, hours: 3)).to eq(5_000)
      expect(member.amount_cents_for(flat_role, hours: 8)).to eq(5_000)
    end

    it "still multiplies an hourly role" do
      expect(member.amount_cents_for(hourly_role, hours: 3)).to eq(6_000)
    end

    it "lets a member's own flat rate override the role default" do
      create(:staff_role_qualification, organization_staff_member: member, house_role: flat_role,
                                        flat_rate_cents: 7_500)
      expect(member.reload.amount_cents_for(flat_role, hours: 4)).to eq(7_500)
    end

    it "reads as per-shift rather than per-hour" do
      expect(member.rate_label_for(flat_role)).to eq("$50.00/shift")
      expect(member.rate_label_for(hourly_role)).to eq("$20.00/hr")
      expect(flat_role.rate_label).to eq("$50.00/shift")
    end
  end

  describe "a pay run" do
    it "prices a flat entry at the flat amount" do
      entry = entry!(flat_role, hours: 6)

      cents = StaffPayRunService.worked_cents(organization: org, member: member, time_entry_ids: [ entry.id ])
      expect(cents).to eq(5_000)
    end

    it "pays a flat shift once even when it was logged as two stints" do
      # (The DB already allows only one entry per shift assignment, so the way
      # a night gets logged twice is two manual entries on the same date.)
      first = entry!(flat_role, hours: 2)
      second = org.staff_time_entries.create!(person: person, house_role: flat_role, hours: 3,
                                              started_at: work_day + 3.hours, ended_at: work_day + 6.hours,
                                              approved_at: Time.current)

      cents = StaffPayRunService.worked_cents(organization: org, member: member,
                                              time_entry_ids: [ first.id, second.id ])
      expect(cents).to eq(5_000)
    end

    it "pays two separate days twice" do
      first = entry!(flat_role, hours: 4)
      second = org.staff_time_entries.create!(person: person, house_role: flat_role, hours: 4,
                                              started_at: work_day - 3.days, ended_at: work_day - 3.days + 4.hours,
                                              approved_at: Time.current)

      cents = StaffPayRunService.worked_cents(organization: org, member: member,
                                              time_entry_ids: [ first.id, second.id ])
      expect(cents).to eq(10_000)
    end

    it "mixes flat and hourly work in one line" do
      flat = entry!(flat_role, hours: 5)
      hourly = entry!(hourly_role, hours: 2)

      cents = StaffPayRunService.worked_cents(organization: org, member: member,
                                              time_entry_ids: [ flat.id, hourly.id ])
      expect(cents).to eq(5_000 + 4_000)
    end
  end

  describe "the employee agreement" do
    it "describes a flat role per shift" do
      create(:staff_role_qualification, organization_staff_member: member, house_role: flat_role)

      expect(member.reload.agreement_schedule_html).to include("Security &mdash; $50.00/shift")
    end
  end
end
