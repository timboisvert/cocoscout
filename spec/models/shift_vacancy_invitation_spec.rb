# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShiftVacancyInvitation, type: :model do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:shift) { create(:shift, organization: org, house_role: create(:house_role, organization: org, name: "Bar")) }
  let(:dana) { create(:person, name: "Dana") }
  let!(:assignment) { shift.shift_assignments.create!(person: dana, position: 1).tap { |a| a.decline!(reason: "Sick") } }
  let(:vacancy) { assignment.active_vacancy }
  let(:priya) { create(:person, name: "Priya") }
  let(:lee) { create(:person, name: "Lee") }

  it "gets a token and an invited_at on create" do
    invitation = vacancy.invitations.create!(person: priya)
    expect(invitation.token).to be_present
    expect(invitation.invited_at).to be_present
  end

  it "claims the shift for the first to claim, and the second finds it taken" do
    first = vacancy.invitations.create!(person: priya)
    second = vacancy.invitations.create!(person: lee)
    vacancy.mark_finding_replacement!

    expect(first.claim!).to be(true)
    expect(first.reload).to be_claimed
    expect(shift.shift_assignments.reload.map(&:person)).to eq([ priya ])
    expect(vacancy.reload).to be_filled

    expect(second.claim!).to be(false)
    expect(second.reload).not_to be_claimed
    expect(second).to be_expired
    expect(second.can_claim?).to be(false)
  end

  it "can't be claimed by someone a manager already put on the shift" do
    invitation = vacancy.invitations.create!(person: priya)
    shift.shift_assignments.create!(person: priya, position: 2)
    expect(invitation.can_claim?).to be(false)
  end

  it "declines, and can still claim while the vacancy is open" do
    invitation = vacancy.invitations.create!(person: priya)
    expect(invitation.decline!).to be(true)
    expect(invitation).to be_declined
    expect(invitation.can_claim?).to be(true)
    expect(invitation.decline!).to be(false)
  end

  describe ".unresolved" do
    it "lists an unclaimed invitation while the vacancy is open or finding cover, not after" do
      invitation = vacancy.invitations.create!(person: priya)
      expect(described_class.unresolved).to include(invitation)
      vacancy.mark_finding_replacement!
      expect(described_class.unresolved).to include(invitation)
      vacancy.mark_not_filling!
      expect(described_class.unresolved).not_to include(invitation)
    end

    it "drops it once the shift is over, however the vacancy stands" do
      invitation = vacancy.invitations.create!(person: priya)
      vacancy.mark_finding_replacement!
      travel_to(shift.ends_at - 1.minute) { expect(described_class.unresolved).to include(invitation) }
      travel_to(shift.ends_at + 1.minute) { expect(described_class.unresolved).not_to include(invitation) }
    end
  end

  # Tim, 2026-11-07: claim invitations go away when the show happens. An old
  # open hole had kept its claim page and home-page card for weeks.
  it "is over once the shift has ended: expired, not claimable, and a claim does nothing" do
    invitation = vacancy.invitations.create!(person: priya)
    vacancy.mark_finding_replacement!
    travel_to(shift.ends_at + 1.hour) do
      expect(invitation).to be_expired
      expect(invitation.can_claim?).to be(false)
      expect(invitation.claim!).to be(false)
      expect(vacancy.reload).to be_finding_replacement
      expect(shift.shift_assignments.active.where(person: priya)).not_to exist
    end
  end
end
