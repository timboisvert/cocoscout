# frozen_string_literal: true

require "rails_helper"

# A shift someone can't make, the performer flow's way: the declined row
# stays as the schedule's hole while the vacancy is active, and every way of
# closing the vacancy resolves the row.
RSpec.describe ShiftVacancy, type: :model do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, owner: create(:user)) }
  let(:role) { create(:house_role, organization: org, name: "Bar") }
  let(:shift) { create(:shift, organization: org, house_role: role, required_count: 2) }
  let(:dana) { create(:person, name: "Dana Morris") }
  let(:priya) { create(:person, name: "Priya Kaur") }
  let!(:assignment) { shift.shift_assignments.create!(person: dana, position: 1, notified_at: 1.day.ago) }

  def enqueued(job)
    enqueued_jobs.select { |j| j["job_class"] == job.name }
  end

  describe "a decline" do
    it "opens one vacancy with the note, and tells the managers once" do
      expect { assignment.decline!(reason: "Out of town") }.to change(described_class, :count).by(1)
      vacancy = described_class.last
      expect(vacancy).to have_attributes(shift: shift, vacated_by: dana, reason: "Out of town", status: "open")
      expect(vacancy.vacated_at).to be_within(1.second).of(assignment.declined_at)
      expect(assignment.active_vacancy).to eq(vacancy)
      expect(enqueued(ShiftDeclinedNotificationJob).map { |j| j["arguments"].first }).to eq([ assignment.id ])

      # Declining again while it's open doesn't open a second one.
      expect { assignment.decline!(reason: "Still away") }.not_to change(described_class, :count)
    end

    it "opens no notice for a shift that's already over" do
      shift.update!(starts_at: 2.days.ago, ends_at: 2.days.ago + 4.hours)
      assignment.decline!
      expect(enqueued(ShiftDeclinedNotificationJob)).to be_empty
    end
  end

  describe "#fill!" do
    before { assignment.decline!(reason: "Sick") }

    let(:vacancy) { assignment.active_vacancy }

    it "takes the dropped row off and puts a claimer on, accepted and told" do
      expect(vacancy.fill!(priya, accepted: true)).to be(true)

      rows = shift.shift_assignments.reload
      expect(rows.map(&:person)).to eq([ priya ])
      expect(rows.first.accepted_at).to be_present
      expect(rows.first.notified_at).to be_present
      expect(vacancy.reload).to have_attributes(status: "filled", filled_by: priya)
      expect(vacancy.filled_at).to be_present
      expect(enqueued(ShiftVacancyNotificationJob).map { |j| j["arguments"] }).to eq([ [ vacancy.id, "filled" ] ])
    end

    it "leaves someone a manager put on by hand still to be told" do
      vacancy.fill!(priya)
      row = shift.shift_assignments.reload.first
      expect(row.person).to eq(priya)
      expect(row.accepted_at).to be_nil
      expect(row.notified_at).to be_nil
    end

    it "does nothing once closed" do
      vacancy.mark_not_filling!
      expect(vacancy.fill!(priya)).to be(false)
    end
  end

  describe ".fill_from_assignment!" do
    it "counts a hand assignment as the cover for the oldest open vacancy" do
      assignment.decline!(reason: "Sick")
      vacancy = assignment.active_vacancy
      replacement = shift.shift_assignments.create!(person: priya, position: 2)

      expect(described_class.fill_from_assignment!(replacement)).to eq(vacancy)
      expect(vacancy.reload).to have_attributes(status: "filled", filled_by: priya)
      expect(shift.shift_assignments.reload.map(&:person)).to eq([ priya ])
      expect(enqueued(ShiftVacancyNotificationJob).map { |j| j["arguments"] }).to eq([ [ vacancy.id, "filled" ] ])
    end

    it "is nothing when no vacancy is open" do
      replacement = shift.shift_assignments.create!(person: priya, position: 2)
      expect(described_class.fill_from_assignment!(replacement)).to be_nil
    end
  end

  describe "#mark_not_filling!" do
    it "closes the hole: the dropped row goes, and it can't be taken back" do
      assignment.decline!
      vacancy = assignment.active_vacancy

      expect(vacancy.mark_not_filling!).to be(true)
      expect(shift.shift_assignments.reload).to be_empty
      expect(vacancy.reload.status).to eq("not_filling")
      expect(vacancy.reclaim!).to be(false)
    end
  end

  describe "#reclaim!" do
    it "puts the row back as it was and tells the managers" do
      assignment.decline!(reason: "Sick")
      vacancy = assignment.active_vacancy

      expect(vacancy.reclaim!).to be(true)
      expect(assignment.reload).to have_attributes(declined_at: nil, decline_reason: nil)
      expect(vacancy.reload.status).to eq("cancelled")
      expect(enqueued(ShiftVacancyNotificationJob).map { |j| j["arguments"] }).to eq([ [ vacancy.id, "reclaimed" ] ])
    end

    it "is refused once someone has covered it" do
      assignment.decline!
      vacancy = assignment.active_vacancy
      vacancy.fill!(priya, accepted: true)
      expect(vacancy.reclaim!).to be(false)
      expect(shift.shift_assignments.reload.map(&:person)).to eq([ priya ])
    end
  end

  describe "#can_invite?" do
    it "says no to the one who dropped it, someone on the shift, or someone asked already" do
      assignment.decline!
      vacancy = assignment.active_vacancy
      on_it = create(:person, name: "Marco")
      shift.shift_assignments.create!(person: on_it, position: 2)
      asked = create(:person, name: "Lee")
      vacancy.invitations.create!(person: asked)

      expect(vacancy.can_invite?(dana)).to be(false)
      expect(vacancy.can_invite?(on_it)).to be(false)
      expect(vacancy.can_invite?(asked)).to be(false)
      expect(vacancy.can_invite?(priya)).to be(true)
    end
  end
end
