# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OrganizationRole, type: :model do
  describe 'associations' do
    it 'belongs to user' do
      organization_role = create(:organization_role)
      expect(organization_role.user).to be_present
      expect(organization_role).to respond_to(:user)
    end

    it 'belongs to organization' do
      organization_role = create(:organization_role)
      expect(organization_role.organization).to be_present
      expect(organization_role).to respond_to(:organization)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      organization_role = build(:organization_role)
      expect(organization_role).to be_valid
    end

    it 'is invalid without a role' do
      organization_role = build(:organization_role, company_role: nil)
      expect(organization_role).not_to be_valid
      expect(organization_role.errors[:company_role]).to include("can't be blank")
    end

    it 'only allows manager, viewer, or none roles' do
      organization_role = build(:organization_role, company_role: 'invalid_role')
      expect(organization_role).not_to be_valid
      expect(organization_role.errors[:company_role]).to include('is not included in the list')
    end

    it 'allows manager role' do
      organization_role = build(:organization_role, :manager)
      expect(organization_role).to be_valid
      expect(organization_role.company_role).to eq('manager')
    end

    it 'allows viewer role' do
      organization_role = build(:organization_role, company_role: 'viewer')
      expect(organization_role).to be_valid
    end

    it 'validates uniqueness of user_id scoped to organization_id' do
      user = create(:user)
      company = create(:organization)
      create(:organization_role, user: user, organization: company)

      duplicate = build(:organization_role, user: user, organization: company)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include('has already been taken')
    end
  end

  describe 'role assignment' do
    it 'connects a user to a production company' do
      organization_role = create(:organization_role)

      expect(organization_role.user).to be_present
      expect(organization_role.organization).to be_present
    end

    it 'allows multiple users for one production company' do
      company = create(:organization)
      user1 = create(:user)
      user2 = create(:user)

      create(:organization_role, user: user1, organization: company, company_role: 'manager')
      create(:organization_role, user: user2, organization: company, company_role: 'viewer')

      expect(company.users).to include(user1, user2)
    end

    it 'allows one user to belong to multiple production companies' do
      user = create(:user)
      company1 = create(:organization)
      company2 = create(:organization)

      create(:organization_role, user: user, organization: company1, company_role: 'manager')
      create(:organization_role, user: user, organization: company2, company_role: 'viewer')

      expect(company1.users).to include(user)
      expect(company2.users).to include(user)
    end
  end
end
