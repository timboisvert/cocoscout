# frozen_string_literal: true

require "rails_helper"

# "I can't make it" used to leave the person assigned, so the shift still read as
# fully staffed and — through Role Call — still counted as covering its show. The
# declined row stays for the manager's sake, but it staffs nothing.
RSpec.describe "Declined shift assignments", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:role) { create(:house_role, organization: org, name: "Bar") }
  let(:shift) do
    create(:shift, organization: org, house_role: role, required_count: 1,
                   starts_at: Time.zone.local(2026, 9, 18, 18), ends_at: Time.zone.local(2026, 9, 18, 23))
  end
  let(:staffer) { create(:person, name: "Quinn") }

  def assign!
    shift.shift_assignments.create!(person: staffer, position: 1)
  end

  it "counts an assignment that still stands" do
    assign!

    expect(shift.reload.assigned_count).to eq(1)
    expect(shift).to be_fully_staffed
    expect(shift.remaining_slots).to eq(0)
  end

  it "stops counting one that was declined, reopening the slot" do
    assignment = assign!
    assignment.decline!(reason: "Out of town")

    shift.reload
    expect(shift.assigned_count).to eq(0)
    expect(shift).not_to be_fully_staffed
    expect(shift.remaining_slots).to eq(1)
  end

  it "keeps the declined person on the shift so the manager can see who dropped" do
    assignment = assign!
    assignment.decline!(reason: "Out of town")

    expect(shift.reload.shift_assignments.map(&:person)).to eq([ staffer ])
    expect(shift.active_assignments).to be_empty
    expect(assignment.reload.decline_reason).to eq("Out of town")
  end

  it "counts again once they say they're back on" do
    assignment = assign!
    assignment.decline!
    assignment.undo_decline!

    expect(shift.reload.assigned_count).to eq(1)
    expect(shift).to be_fully_staffed
  end

  it "only counts the people still standing when a shift needs several" do
    shift.update!(required_count: 3)
    first = assign!
    shift.shift_assignments.create!(person: create(:person), position: 2)
    shift.shift_assignments.create!(person: create(:person), position: 3)
    first.decline!

    shift.reload
    expect(shift.assigned_count).to eq(2)
    expect(shift.remaining_slots).to eq(1)
    expect(shift).not_to be_fully_staffed
  end

  describe "ShiftAssignment#active?" do
    it "is true until they decline, and true again after they undo it" do
      assignment = assign!
      expect(assignment).to be_active

      assignment.decline!
      expect(assignment).not_to be_active
      expect(ShiftAssignment.active).not_to include(assignment)

      assignment.undo_decline!
      expect(assignment).to be_active
      expect(ShiftAssignment.active).to include(assignment)
    end
  end
end
