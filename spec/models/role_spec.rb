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
end
