# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GroupInvitation, type: :model do
  describe 'associations' do
    it 'belongs to a group' do
      invitation = build(:group_invitation)
      expect(invitation).to respond_to(:group)
    end

    it 'optionally belongs to an invited_by person' do
      invitation = build(:group_invitation)
      expect(invitation).to respond_to(:invited_by)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:group_invitation)).to be_valid
    end

    it 'is invalid without an email' do
      invitation = build(:group_invitation, email: nil)
      expect(invitation).not_to be_valid
      expect(invitation.errors[:email]).to include("can't be blank")
    end

    it 'is invalid without a name' do
      invitation = build(:group_invitation, name: nil)
      expect(invitation).not_to be_valid
      expect(invitation.errors[:name]).to include("can't be blank")
    end

    it 'enforces token uniqueness' do
      create(:group_invitation, token: 'unique-token')
      duplicate = build(:group_invitation, token: 'unique-token')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token]).to include("has already been taken")
    end

    it 'validates email format' do
      invitation = build(:group_invitation, email: 'invalid')
      expect(invitation).not_to be_valid
      expect(invitation.errors[:email]).to be_present
    end

    it 'accepts valid email format' do
      invitation = build(:group_invitation, email: 'valid@example.com')
      expect(invitation).to be_valid
    end
  end

  describe 'enums' do
    it 'defines permission levels' do
      expect(described_class.permission_levels).to eq({
        'owner' => 0,
        'write' => 1,
        'view' => 2
      })
    end
  end

  describe 'scopes' do
    describe '.pending' do
      it 'returns only invitations without accepted_at' do
        pending = create(:group_invitation, accepted_at: nil)
        accepted = create(:group_invitation, accepted_at: Time.current)

        expect(described_class.pending).to include(pending)
        expect(described_class.pending).not_to include(accepted)
      end
    end

    describe '.accepted' do
      it 'returns only invitations with accepted_at' do
        pending = create(:group_invitation, accepted_at: nil)
        accepted = create(:group_invitation, accepted_at: Time.current)

        expect(described_class.accepted).to include(accepted)
        expect(described_class.accepted).not_to include(pending)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'generates a token on create' do
        invitation = build(:group_invitation, token: nil)
        invitation.valid?
        expect(invitation.token).to be_present
        expect(invitation.token.length).to eq(40)
      end

      it 'normalizes email to lowercase' do
        invitation = build(:group_invitation, email: 'TEST@EXAMPLE.COM')
        invitation.valid?
        expect(invitation.email).to eq('test@example.com')
      end

      it 'strips whitespace from email' do
        invitation = build(:group_invitation, email: '  test@example.com  ')
        invitation.valid?
        expect(invitation.email).to eq('test@example.com')
      end
    end
  end

  describe '#accepted?' do
    it 'returns true when accepted_at is present' do
      invitation = build(:group_invitation, accepted_at: Time.current)
      expect(invitation.accepted?).to be true
    end

    it 'returns false when accepted_at is nil' do
      invitation = build(:group_invitation, accepted_at: nil)
      expect(invitation.accepted?).to be false
    end
  end

  describe '#pending?' do
    it 'returns true when accepted_at is nil' do
      invitation = build(:group_invitation, accepted_at: nil)
      expect(invitation.pending?).to be true
    end

    it 'returns false when accepted_at is present' do
      invitation = build(:group_invitation, accepted_at: Time.current)
      expect(invitation.pending?).to be false
    end
  end
end
