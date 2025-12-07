# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShowPersonRoleAssignment, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      assignment = build(:show_person_role_assignment)
      expect(assignment).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to show' do
      assignment = build(:show_person_role_assignment)
      expect(assignment).to respond_to(:show)
    end

    it 'belongs to person' do
      assignment = build(:show_person_role_assignment)
      expect(assignment).to respond_to(:person)
    end

    it 'belongs to role' do
      assignment = build(:show_person_role_assignment)
      expect(assignment).to respond_to(:role)
    end
  end

  describe 'creating assignments' do
    it 'can assign a person to a role in a show' do
      show = create(:show)
      person = create(:person)
      role = create(:role, production: show.production)

      assignment = create(:show_person_role_assignment,
                          show: show,
                          person: person,
                          role: role)

      expect(assignment).to be_persisted
      expect(assignment.show).to eq(show)
      expect(assignment.person).to eq(person)
      expect(assignment.role).to eq(role)
    end
  end
end
