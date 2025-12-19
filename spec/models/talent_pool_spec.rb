# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TalentPool, type: :model do
  describe 'associations' do
    it 'belongs to a production' do
      talent_pool = build(:talent_pool)
      expect(talent_pool).to respond_to(:production)
    end

    it 'has many talent_pool_memberships' do
      talent_pool = create(:talent_pool)
      expect(talent_pool).to respond_to(:talent_pool_memberships)
    end

    it 'has many people through talent_pool_memberships' do
      talent_pool = create(:talent_pool)
      expect(talent_pool).to respond_to(:people)
    end

    it 'has many groups through talent_pool_memberships' do
      talent_pool = create(:talent_pool)
      expect(talent_pool).to respond_to(:groups)
    end

    it 'has many cast_assignment_stages' do
      talent_pool = create(:talent_pool)
      expect(talent_pool).to respond_to(:cast_assignment_stages)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:talent_pool)).to be_valid
    end

    it 'is invalid without a name' do
      talent_pool = build(:talent_pool, name: nil)
      expect(talent_pool).not_to be_valid
      expect(talent_pool.errors[:name]).to include("can't be blank")
    end
  end

  describe '#members' do
    it 'returns all members including people and groups' do
      production = create(:production)
      talent_pool = create(:talent_pool, production: production)
      person = create(:person)
      group = create(:group)

      create(:talent_pool_membership, talent_pool: talent_pool, member: person)
      create(:talent_pool_membership, talent_pool: talent_pool, member: group)

      expect(talent_pool.members).to include(person, group)
    end
  end

  describe '#cached_member_counts' do
    it 'returns counts by type' do
      production = create(:production)
      talent_pool = create(:talent_pool, production: production)
      person1 = create(:person)
      person2 = create(:person)
      group = create(:group)

      create(:talent_pool_membership, talent_pool: talent_pool, member: person1)
      create(:talent_pool_membership, talent_pool: talent_pool, member: person2)
      create(:talent_pool_membership, talent_pool: talent_pool, member: group)

      counts = talent_pool.cached_member_counts

      expect(counts[:people]).to eq(2)
      expect(counts[:groups]).to eq(1)
      expect(counts[:total]).to eq(3)
    end
  end
end
