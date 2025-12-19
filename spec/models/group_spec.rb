# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Group, type: :model do
  describe 'associations' do
    it 'has many group_memberships' do
      group = create(:group)
      expect(group).to respond_to(:group_memberships)
    end

    it 'has many group_invitations' do
      group = create(:group)
      expect(group).to respond_to(:group_invitations)
    end

    it 'has many members through group_memberships' do
      group = create(:group)
      expect(group).to respond_to(:members)
    end

    it 'has many socials' do
      group = create(:group)
      expect(group).to respond_to(:socials)
    end

    it 'has many profile_headshots' do
      group = create(:group)
      expect(group).to respond_to(:profile_headshots)
    end

    it 'has many profile_videos' do
      group = create(:group)
      expect(group).to respond_to(:profile_videos)
    end

    it 'has many performance_credits' do
      group = create(:group)
      expect(group).to respond_to(:performance_credits)
    end

    it 'has many profile_skills' do
      group = create(:group)
      expect(group).to respond_to(:profile_skills)
    end

    it 'has many profile_resumes' do
      group = create(:group)
      expect(group).to respond_to(:profile_resumes)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:group)).to be_valid
    end

    it 'is invalid without a name' do
      group = build(:group, name: nil)
      expect(group).not_to be_valid
      expect(group.errors[:name]).to include("can't be blank")
    end

    it 'is invalid without an email' do
      group = build(:group, email: nil)
      expect(group).not_to be_valid
      expect(group.errors[:email]).to include("can't be blank")
    end

    it 'enforces public_key uniqueness' do
      create(:group, public_key: 'unique-key')
      duplicate = build(:group, public_key: 'unique-key')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:public_key]).to include("has already been taken")
    end

    describe 'public_key format' do
      it 'allows valid public keys' do
        group = build(:group, public_key: 'valid-key-123')
        expect(group).to be_valid
      end

      it 'downcases uppercase characters before validation' do
        group = build(:group, public_key: 'Invalid-Key')
        group.valid?
        expect(group.public_key).to eq('invalid-key')
      end

      it 'rejects keys that are too short' do
        group = build(:group, public_key: 'ab')
        expect(group).not_to be_valid
      end

      it 'rejects keys that are too long' do
        group = build(:group, public_key: 'a' * 31)
        expect(group).not_to be_valid
      end

      it 'rejects keys starting with a hyphen' do
        group = build(:group, public_key: '-invalid')
        expect(group).not_to be_valid
      end
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only groups without archived_at' do
        active_group = create(:group)
        archived_group = create(:group, archived_at: Time.current)

        expect(Group.active).to include(active_group)
        expect(Group.active).not_to include(archived_group)
      end
    end

    describe '.archived' do
      it 'returns only groups with archived_at' do
        active_group = create(:group)
        archived_group = create(:group, archived_at: Time.current)

        expect(Group.archived).to include(archived_group)
        expect(Group.archived).not_to include(active_group)
      end
    end
  end

  describe '#archived?' do
    it 'returns false when archived_at is nil' do
      group = build(:group, archived_at: nil)
      expect(group.archived?).to be false
    end

    it 'returns true when archived_at is present' do
      group = build(:group, archived_at: Time.current)
      expect(group.archived?).to be true
    end
  end

  describe '#archive!' do
    it 'sets archived_at to current time' do
      group = create(:group)
      expect { group.archive! }.to change { group.archived? }.from(false).to(true)
    end
  end

  describe '#unarchive!' do
    it 'clears archived_at' do
      group = create(:group, archived_at: Time.current)
      expect { group.unarchive! }.to change { group.archived? }.from(true).to(false)
    end
  end

  describe '#initials' do
    it 'returns first letters of each word' do
      group = build(:group, name: 'The Comedy Troupe')
      expect(group.initials).to eq('TCT')
    end

    it 'returns empty string for blank names' do
      group = build(:group, name: '')
      expect(group.initials).to eq('')
    end

    it 'handles single word names' do
      group = build(:group, name: 'Improv')
      expect(group.initials).to eq('I')
    end
  end

  describe '#update_public_key' do
    it 'updates the public key and stores the old one' do
      group = create(:group, public_key: 'old-key')
      group.update_public_key('new-key')

      expect(group.public_key).to eq('new-key')
      expect(JSON.parse(group.old_keys)).to include('old-key')
    end

    it 'returns false if key is the same' do
      group = create(:group, public_key: 'same-key')
      result = group.update_public_key('same-key')

      expect(result).to be false
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'generates a public_key on create if not provided' do
        group = build(:group, public_key: nil)
        group.valid?
        expect(group.public_key).to be_present
      end

      it 'downcases public_key' do
        group = build(:group, public_key: 'UPPERCASE')
        group.valid?
        expect(group.public_key).to eq('uppercase')
      end
    end
  end
end
