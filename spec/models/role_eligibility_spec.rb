# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoleEligibility, type: :model do
  describe 'associations' do
    it 'belongs to role' do
      role_eligibility = create(:role_eligibility)
      expect(role_eligibility.role).to be_present
      expect(role_eligibility).to respond_to(:role)
    end

    it 'belongs to member (polymorphic)' do
      role_eligibility = create(:role_eligibility)
      expect(role_eligibility.member).to be_present
      expect(role_eligibility).to respond_to(:member)
    end

    it 'can have a Person as member' do
      person = create(:person)
      role_eligibility = create(:role_eligibility, member: person)
      expect(role_eligibility.member).to eq(person)
      expect(role_eligibility.member_type).to eq("Person")
    end

    it 'can have a Group as member' do
      group = create(:group)
      role_eligibility = create(:role_eligibility, member: group)
      expect(role_eligibility.member).to eq(group)
      expect(role_eligibility.member_type).to eq("Group")
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      role_eligibility = build(:role_eligibility)
      expect(role_eligibility).to be_valid
    end

    it 'prevents duplicate member-role combinations' do
      role = create(:role)
      person = create(:person)
      create(:role_eligibility, role: role, member: person)

      duplicate = build(:role_eligibility, role: role, member: person)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:member_id]).to include("is already eligible for this role")
    end

    it 'allows the same member to be eligible for different roles' do
      person = create(:person)
      role1 = create(:role)
      role2 = create(:role)

      eligibility1 = create(:role_eligibility, member: person, role: role1)
      eligibility2 = build(:role_eligibility, member: person, role: role2)

      expect(eligibility2).to be_valid
    end

    it 'allows different member types with same ID for the same role' do
      role = create(:role)
      person = create(:person)
      group = create(:group)

      # Create eligibility for person
      create(:role_eligibility, role: role, member: person)

      # Should be able to create eligibility for group even if IDs happen to match
      eligibility = build(:role_eligibility, role: role, member: group)
      expect(eligibility).to be_valid
    end
  end
end
