# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TalentPoolMembership, type: :model do
  describe 'associations' do
    it 'belongs to a talent_pool' do
      membership = TalentPoolMembership.new
      expect(membership).to respond_to(:talent_pool)
    end

    it 'belongs to a member (polymorphic)' do
      membership = TalentPoolMembership.new
      expect(membership).to respond_to(:member)
    end
  end

  describe 'validations' do
    let(:production) { create(:production) }
    let(:talent_pool) { create(:talent_pool, production: production) }
    let(:person) { create(:person) }

    it 'is valid with valid attributes' do
      membership = TalentPoolMembership.new(talent_pool: talent_pool, member: person)
      expect(membership).to be_valid
    end

    it 'is invalid without a talent_pool' do
      membership = TalentPoolMembership.new(talent_pool: nil, member: person)
      expect(membership).not_to be_valid
      expect(membership.errors[:talent_pool]).to include("can't be blank")
    end

    it 'is invalid without a member' do
      membership = TalentPoolMembership.new(talent_pool: talent_pool, member: nil)
      expect(membership).not_to be_valid
      expect(membership.errors[:member]).to include("can't be blank")
    end

    it 'enforces uniqueness of member within a talent pool' do
      TalentPoolMembership.create!(talent_pool: talent_pool, member: person)
      duplicate = TalentPoolMembership.new(talent_pool: talent_pool, member: person)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:member_id]).to include("has already been taken")
    end

    it 'allows the same person in different talent pools' do
      other_talent_pool = create(:talent_pool, production: production)
      TalentPoolMembership.create!(talent_pool: talent_pool, member: person)
      membership = TalentPoolMembership.new(talent_pool: other_talent_pool, member: person)
      expect(membership).to be_valid
    end

    it 'allows different members of same type in the same talent pool' do
      other_person = create(:person)
      TalentPoolMembership.create!(talent_pool: talent_pool, member: person)
      membership = TalentPoolMembership.new(talent_pool: talent_pool, member: other_person)
      expect(membership).to be_valid
    end
  end

  describe 'pool membership implies org membership' do
    let(:org) { create(:organization) }
    let(:production) { create(:production, organization: org) }
    let(:pool) { create(:talent_pool, production: production) }

    it 'adds a person to the pool\'s organization when they join the pool' do
      person = create(:person)
      expect(org.people.exists?(person.id)).to be(false)

      TalentPoolMembership.create!(talent_pool: pool, member: person)

      expect(org.people.exists?(person.id)).to be(true)
    end

    it 'works through the association shovel too (pool.people <<)' do
      person = create(:person)
      pool.people << person
      expect(org.people.exists?(person.id)).to be(true)
    end

    it 'does not duplicate an existing org membership' do
      person = create(:person)
      org.people << person
      expect {
        TalentPoolMembership.create!(talent_pool: pool, member: person)
      }.not_to(change { org.people.where(id: person.id).count })
    end
  end
end
