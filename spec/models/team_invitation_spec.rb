# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamInvitation, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      team_invitation = build(:team_invitation)
      expect(team_invitation).to be_valid
    end

    it 'is invalid without an email' do
      team_invitation = build(:team_invitation, email: nil)
      expect(team_invitation).not_to be_valid
      expect(team_invitation.errors[:email]).to include("can't be blank")
    end

    it 'requires unique tokens' do
      create(:team_invitation, token: 'unique_token')
      duplicate = build(:team_invitation, token: 'unique_token')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token]).to include('has already been taken')
    end
  end

  describe 'associations' do
    it 'belongs to organization' do
      team_invitation = build(:team_invitation)
      expect(team_invitation).to respond_to(:organization)
    end
  end

  describe 'callbacks' do
    describe '#generate_token' do
      it 'generates a token before validation on create' do
        team_invitation = build(:team_invitation, token: nil)
        team_invitation.valid?
        expect(team_invitation.token).to be_present
      end

      it 'does not override an existing token' do
        team_invitation = build(:team_invitation, token: 'existing_token')
        team_invitation.valid?
        expect(team_invitation.token).to eq('existing_token')
      end

      it 'generates a unique hex token' do
        team_invitation = create(:team_invitation, token: nil)
        expect(team_invitation.token).to match(/\A[a-f0-9]{40}\z/)
      end
    end
  end
end
