# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organization, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      company = build(:organization)
      expect(company).to be_valid
    end

    it 'is invalid without a name' do
      company = build(:organization, name: nil)
      expect(company).not_to be_valid
      expect(company.errors[:name]).to include("can't be blank")
    end
  end

  describe 'associations' do
    it 'has many productions' do
      company = create(:organization)
      expect(company).to respond_to(:productions)
    end

    it 'has many organization_roles' do
      company = create(:organization)
      expect(company).to respond_to(:organization_roles)
    end

    it 'has many users through organization_roles' do
      company = create(:organization)
      expect(company).to respond_to(:users)
    end

    it 'has many locations' do
      company = create(:organization)
      expect(company).to respond_to(:locations)
    end
  end

  describe 'dependent destroy behavior' do
    let(:company) { create(:organization) }

    it 'destroys associated productions when destroyed' do
      create(:production, organization: company)
      create(:production, organization: company)

      expect { company.destroy }.to change { Production.count }.by(-2)
    end

    it 'destroys associated locations when destroyed' do
      create(:location, organization: company)
      create(:location, organization: company)

      expect { company.destroy }.to change { Location.count }.by(-2)
    end

    it 'cascades destroy to productions and their shows' do
      production = create(:production, organization: company)
      create(:show, production: production)
      create(:show, production: production)

      expect { company.destroy }.to change { Show.count }.by(-2)
    end
  end

  describe 'with multiple productions' do
    it 'can have multiple productions' do
      company = create(:organization)
      production1 = create(:production, organization: company, name: 'Hamilton')
      production2 = create(:production, organization: company, name: 'Wicked')

      expect(company.productions).to include(production1, production2)
      expect(company.productions.count).to eq(2)
    end
  end

  describe 'with users and roles' do
    it 'can have multiple users through organization_roles' do
      company = create(:organization)
      user1 = create(:user)
      user2 = create(:user)

      create(:organization_role, user: user1, organization: company, company_role: 'manager')
      create(:organization_role, user: user2, organization: company, company_role: 'viewer')

      expect(company.users.reload).to include(user1, user2)
      expect(company.users.count).to eq(2)
    end
  end
end
