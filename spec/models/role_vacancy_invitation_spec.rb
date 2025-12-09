# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoleVacancyInvitation, type: :model do
  describe "associations" do
    it "belongs to role_vacancy" do
      invitation = build(:role_vacancy_invitation)
      expect(invitation.role_vacancy).to be_present
    end

    it "belongs to person" do
      invitation = build(:role_vacancy_invitation)
      expect(invitation.person).to be_present
    end

    it "delegates role to role_vacancy" do
      invitation = create(:role_vacancy_invitation)
      expect(invitation.role).to eq(invitation.role_vacancy.role)
    end

    it "delegates show to role_vacancy" do
      invitation = create(:role_vacancy_invitation)
      expect(invitation.show).to eq(invitation.role_vacancy.show)
    end
  end

  describe "token generation" do
    it "generates a token before create" do
      invitation = build(:role_vacancy_invitation)
      expect(invitation.token).to be_nil
      invitation.save!
      expect(invitation.token).to be_present
    end

    it "generates unique tokens" do
      inv1 = create(:role_vacancy_invitation)
      inv2 = create(:role_vacancy_invitation)
      expect(inv1.token).not_to eq(inv2.token)
    end
  end

  describe "invited_at" do
    it "sets invited_at before create" do
      invitation = build(:role_vacancy_invitation, invited_at: nil)
      invitation.save!
      expect(invitation.invited_at).to be_present
    end

    it "preserves existing invited_at" do
      time = 1.day.ago
      invitation = build(:role_vacancy_invitation, invited_at: time)
      invitation.save!
      expect(invitation.invited_at).to be_within(1.second).of(time)
    end
  end

  describe "scopes" do
    let!(:pending_invitation) { create(:role_vacancy_invitation) }
    let!(:claimed_invitation) { create(:role_vacancy_invitation, :claimed) }

    describe ".pending" do
      it "returns unclaimed invitations" do
        expect(described_class.pending).to include(pending_invitation)
        expect(described_class.pending).not_to include(claimed_invitation)
      end
    end

    describe ".claimed" do
      it "returns claimed invitations" do
        expect(described_class.claimed).to include(claimed_invitation)
        expect(described_class.claimed).not_to include(pending_invitation)
      end
    end
  end

  describe "#claimed?" do
    it "returns false for unclaimed invitation" do
      invitation = build(:role_vacancy_invitation, claimed_at: nil)
      expect(invitation.claimed?).to be false
    end

    it "returns true for claimed invitation" do
      invitation = build(:role_vacancy_invitation, :claimed)
      expect(invitation.claimed?).to be true
    end
  end

  describe "#pending?" do
    it "returns true for unclaimed invitation" do
      invitation = build(:role_vacancy_invitation, claimed_at: nil)
      expect(invitation.pending?).to be true
    end

    it "returns false for claimed invitation" do
      invitation = build(:role_vacancy_invitation, :claimed)
      expect(invitation.pending?).to be false
    end
  end

  describe "#claim!" do
    let(:vacancy) { create(:role_vacancy) }
    let(:person) { create(:person) }
    let(:invitation) { create(:role_vacancy_invitation, role_vacancy: vacancy, person: person) }

    context "when invitation is pending and vacancy is open" do
      it "claims the invitation" do
        result = invitation.claim!

        expect(result).to be true
        expect(invitation.claimed?).to be true
        expect(invitation.claimed_at).to be_present
      end

      it "fills the vacancy with the person" do
        invitation.claim!

        vacancy.reload
        expect(vacancy).to be_filled
        expect(vacancy.filled_by).to eq(person)
      end
    end

    context "when invitation is already claimed" do
      before { invitation.update!(claimed_at: 1.hour.ago) }

      it "returns false" do
        expect(invitation.claim!).to be false
      end
    end

    context "when vacancy is no longer open" do
      before { vacancy.update!(status: :cancelled) }

      it "returns false" do
        expect(invitation.claim!).to be false
      end
    end
  end

  describe "#expired?" do
    it "returns false when vacancy is open" do
      invitation = create(:role_vacancy_invitation)
      expect(invitation.expired?).to be false
    end

    it "returns true when vacancy is filled" do
      vacancy = create(:role_vacancy, :filled)
      invitation = create(:role_vacancy_invitation, role_vacancy: vacancy)
      expect(invitation.expired?).to be true
    end

    it "returns true when vacancy is cancelled" do
      vacancy = create(:role_vacancy, :cancelled)
      invitation = create(:role_vacancy_invitation, role_vacancy: vacancy)
      expect(invitation.expired?).to be true
    end
  end
end
