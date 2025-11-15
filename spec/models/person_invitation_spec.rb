require 'rails_helper'

RSpec.describe PersonInvitation, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      person_invitation = build(:person_invitation)
      expect(person_invitation).to be_valid
    end

    it "is invalid without an email" do
      person_invitation = build(:person_invitation, email: nil)
      expect(person_invitation).not_to be_valid
      expect(person_invitation.errors[:email]).to include("can't be blank")
    end

    it "requires unique tokens" do
      create(:person_invitation, token: "unique_token")
      duplicate = build(:person_invitation, token: "unique_token")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "belongs to organization" do
      person_invitation = build(:person_invitation)
      expect(person_invitation).to respond_to(:organization)
    end
  end

  describe "callbacks" do
    describe "#generate_token" do
      it "generates a token before validation on create" do
        person_invitation = build(:person_invitation, token: nil)
        person_invitation.valid?
        expect(person_invitation.token).to be_present
      end

      it "does not override an existing token" do
        person_invitation = build(:person_invitation, token: "existing_token")
        person_invitation.valid?
        expect(person_invitation.token).to eq("existing_token")
      end

      it "generates a unique hex token" do
        person_invitation = create(:person_invitation, token: nil)
        expect(person_invitation.token).to match(/\A[a-f0-9]{40}\z/)
      end
    end
  end
end
