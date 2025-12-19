# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GroupMembership, type: :model do
  describe 'associations' do
    it 'belongs to a group' do
      membership = build(:group_membership)
      expect(membership).to respond_to(:group)
    end

    it 'belongs to a person' do
      membership = build(:group_membership)
      expect(membership).to respond_to(:person)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:group_membership)).to be_valid
    end

    it 'is invalid without a group' do
      membership = build(:group_membership, group: nil)
      expect(membership).not_to be_valid
    end

    it 'is invalid without a person' do
      membership = build(:group_membership, person: nil)
      expect(membership).not_to be_valid
    end

    it 'validates uniqueness of person within a group' do
      group = create(:group)
      person = create(:person)
      create(:group_membership, group: group, person: person)

      duplicate = build(:group_membership, group: group, person: person)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:person_id]).to include('is already a member of this group')
    end
  end

  describe 'enums' do
    it 'defines permission levels' do
      expect(described_class.permission_levels).to eq({
        'view' => 0,
        'write' => 1,
        'owner' => 2
      })
    end
  end

  describe 'scopes' do
    describe '.visible_on_profile' do
      it 'returns only memberships with show_on_profile true' do
        visible = create(:group_membership, show_on_profile: true)
        hidden = create(:group_membership, show_on_profile: false)

        expect(described_class.visible_on_profile).to include(visible)
        expect(described_class.visible_on_profile).not_to include(hidden)
      end
    end
  end

  describe '#notifications_enabled?' do
    it 'returns true for owners regardless of setting' do
      membership = build(:group_membership, permission_level: :owner)
      membership.notification_preferences = { 'enabled' => false }
      expect(membership.notifications_enabled?).to be true
    end

    it 'returns true by default for non-owners' do
      membership = build(:group_membership, permission_level: :write)
      expect(membership.notifications_enabled?).to be true
    end

    it 'returns false when explicitly disabled for non-owners' do
      membership = build(:group_membership, permission_level: :write)
      membership.notification_preferences = { 'enabled' => false }
      expect(membership.notifications_enabled?).to be false
    end
  end

  describe '#enable_notifications!' do
    it 'sets notifications to enabled' do
      membership = create(:group_membership, permission_level: :write)
      membership.notification_preferences = { 'enabled' => false }
      membership.save!

      membership.enable_notifications!
      expect(membership.reload.notifications_enabled?).to be true
    end
  end

  describe '#disable_notifications!' do
    it 'sets notifications to disabled for non-owners' do
      membership = create(:group_membership, permission_level: :write)
      result = membership.disable_notifications!

      expect(result).to be true
      expect(membership.reload.notifications_enabled?).to be false
    end

    it 'returns false and does not disable for owners' do
      membership = create(:group_membership, permission_level: :owner)
      result = membership.disable_notifications!

      expect(result).to be false
      expect(membership.reload.notifications_enabled?).to be true
    end
  end
end
