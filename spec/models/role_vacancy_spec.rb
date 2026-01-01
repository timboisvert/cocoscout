# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoleVacancy, type: :model do
  describe "associations" do
    it "belongs to show" do
      vacancy = build(:role_vacancy)
      expect(vacancy.show).to be_present
    end

    it "belongs to role" do
      vacancy = build(:role_vacancy)
      expect(vacancy.role).to be_present
    end

    it "has optional vacated_by association" do
      vacancy = create(:role_vacancy)
      expect(vacancy.vacated_by).to be_nil

      person = create(:person)
      vacancy.update!(vacated_by: person)
      expect(vacancy.vacated_by).to eq(person)
    end

    it "has many invitations" do
      vacancy = create(:role_vacancy)
      invitation = create(:role_vacancy_invitation, role_vacancy: vacancy)
      expect(vacancy.invitations).to include(invitation)
    end
  end

  describe "validations" do
    it "requires a status" do
      vacancy = build(:role_vacancy, status: nil)
      expect(vacancy).not_to be_valid
    end
  end

  describe "status enum" do
    it "has the correct statuses" do
      expect(described_class.statuses).to eq({
        "open" => "open",
        "filled" => "filled",
        "cancelled" => "cancelled",
        "finding_replacement" => "finding_replacement",
        "not_filling" => "not_filling"
      })
    end
  end

  describe "#fill!" do
    let(:vacancy) { create(:role_vacancy) }
    let(:person) { create(:person) }
    let(:closer) { create(:user) }

    it "fills the vacancy with the person" do
      vacancy.fill!(person, by: closer)

      expect(vacancy).to be_filled
      expect(vacancy.filled_by).to eq(person)
      expect(vacancy.filled_at).to be_present
      expect(vacancy.closed_at).to be_present
      expect(vacancy.closed_by).to eq(closer)
    end
  end

  describe "#cancel!" do
    let(:vacancy) { create(:role_vacancy) }
    let(:closer) { create(:user) }

    it "cancels the vacancy" do
      vacancy.cancel!(by: closer)

      expect(vacancy).to be_cancelled
      expect(vacancy.closed_at).to be_present
      expect(vacancy.closed_by).to eq(closer)
    end
  end

  describe "#can_invite?" do
    let(:vacancy) { create(:role_vacancy) }
    let(:person) { create(:person) }

    context "when vacancy is open and person hasn't been invited" do
      it "returns true" do
        expect(vacancy.can_invite?(person)).to be true
      end
    end

    context "when person has already been invited" do
      before do
        create(:role_vacancy_invitation, role_vacancy: vacancy, person: person)
      end

      it "returns false" do
        expect(vacancy.can_invite?(person)).to be false
      end
    end

    context "when vacancy is not open" do
      before { vacancy.update!(status: :filled) }

      it "returns false" do
        expect(vacancy.can_invite?(person)).to be false
      end
    end
  end
end
