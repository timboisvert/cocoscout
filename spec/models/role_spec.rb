# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Role, type: :model do
  describe 'associations' do
    it 'belongs to production' do
      role = create(:role)
      expect(role.production).to be_present
      expect(role).to respond_to(:production)
    end

    it 'has many show_person_role_assignments' do
      role = create(:role)
      expect(role).to respond_to(:show_person_role_assignments)
    end

    it 'has many shows through show_person_role_assignments' do
      role = create(:role)
      expect(role).to respond_to(:shows)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      role = build(:role)
      expect(role).to be_valid
    end

    it 'is invalid without a name' do
      role = build(:role, name: nil)
      expect(role).not_to be_valid
      expect(role.errors[:name]).to include("can't be blank")
    end
  end

  describe 'role creation' do
    it 'can be created with a name and production' do
      production = create(:production)
      role = production.roles.create(name: 'Ensemble Member')

      expect(role.name).to eq('Ensemble Member')
      expect(role.production).to eq(production)
    end

    it 'can be associated with multiple shows' do
      production = create(:production)
      role = create(:role, production: production)

      # This would require ShowPersonRoleAssignment factory and more setup
      # Just test the association exists
      expect(role).to respond_to(:shows)
    end
  end

  describe 'role eligibility' do
    it 'has many role_eligibilities' do
      role = create(:role)
      expect(role).to respond_to(:role_eligibilities)
    end

    it 'responds to eligible_members' do
      role = create(:role)
      expect(role).to respond_to(:eligible_members)
    end

    it 'responds to eligible_people' do
      role = create(:role)
      expect(role).to respond_to(:eligible_people)
    end

    it 'responds to eligible_groups' do
      role = create(:role)
      expect(role).to respond_to(:eligible_groups)
    end

    it 'defaults restricted to false' do
      role = create(:role)
      expect(role.restricted?).to be false
    end

    describe '#eligible?' do
      let(:role) { create(:role) }  # Start unrestricted
      let(:person) { create(:person) }
      let(:group) { create(:group) }

      it 'returns true for eligible person' do
        create(:role_eligibility, role: role, member: person)
        role.update!(restricted: true)
        expect(role.eligible?(person)).to be true
      end

      it 'returns true for eligible group' do
        create(:role_eligibility, role: role, member: group)
        role.update!(restricted: true)
        expect(role.eligible?(group)).to be true
      end

      it 'returns false for ineligible member' do
        # Create eligibility for someone else so role can be restricted
        other_person = create(:person)
        create(:role_eligibility, role: role, member: other_person)
        role.update!(restricted: true)
        expect(role.eligible?(person)).to be false
      end

      it 'returns true for any member when role is not restricted' do
        expect(role.eligible?(person)).to be true
      end
    end

    describe '#eligible_assignees' do
      let(:organization) { create(:organization) }
      let(:production) { create(:production, organization: organization) }
      let(:talent_pool) { create(:talent_pool, production: production) }
      let(:role) { create(:role, production: production) }

      let(:person1) { create(:person, organizations: [ organization ]) }
      let(:person2) { create(:person, organizations: [ organization ]) }
      let(:person3) { create(:person, organizations: [ organization ]) }
      let(:group1) { create(:group, organizations: [ organization ]) }

      before do
        # Add all members to the talent pool
        create(:talent_pool_membership, talent_pool: talent_pool, member: person1)
        create(:talent_pool_membership, talent_pool: talent_pool, member: person2)
        create(:talent_pool_membership, talent_pool: talent_pool, member: person3)
        create(:talent_pool_membership, talent_pool: talent_pool, member: group1)
      end

      context 'when role is not restricted' do
        it 'returns all talent pool members including groups' do
          eligible = role.eligible_assignees([ talent_pool.id ])
          expect(eligible).to include(person1, person2, person3, group1)
        end
      end

      context 'when role is restricted' do
        it 'returns only eligible members who are also in the talent pool' do
          create(:role_eligibility, role: role, member: person1)
          create(:role_eligibility, role: role, member: group1)
          role.update!(restricted: true)

          eligible = role.eligible_assignees([ talent_pool.id ])
          expect(eligible).to include(person1, group1)
          expect(eligible).not_to include(person2, person3)
        end

        it 'does not return eligible members who are not in the talent pool' do
          person_not_in_pool = create(:person, organizations: [ organization ])
          create(:role_eligibility, role: role, member: person1)  # Need at least one eligible
          create(:role_eligibility, role: role, member: person_not_in_pool)
          role.update!(restricted: true)

          eligible = role.eligible_assignees([ talent_pool.id ])
          expect(eligible).not_to include(person_not_in_pool)
        end
      end
    end
  end
end
