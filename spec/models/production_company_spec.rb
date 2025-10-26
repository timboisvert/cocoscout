require 'rails_helper'

RSpec.describe ProductionCompany, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      company = build(:production_company)
      expect(company).to be_valid
    end

    it "is invalid without a name" do
      company = build(:production_company, name: nil)
      expect(company).not_to be_valid
      expect(company.errors[:name]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "has many productions" do
      company = create(:production_company)
      expect(company).to respond_to(:productions)
    end

    it "has many user_roles" do
      company = create(:production_company)
      expect(company).to respond_to(:user_roles)
    end

    it "has many users through user_roles" do
      company = create(:production_company)
      expect(company).to respond_to(:users)
    end

    it "has many locations" do
      company = create(:production_company)
      expect(company).to respond_to(:locations)
    end
  end

  describe "dependent destroy behavior" do
    let(:company) { create(:production_company) }

    it "destroys associated productions when destroyed" do
      create(:production, production_company: company)
      create(:production, production_company: company)

      expect { company.destroy }.to change { Production.count }.by(-2)
    end

    it "destroys associated locations when destroyed" do
      create(:location, production_company: company)
      create(:location, production_company: company)

      expect { company.destroy }.to change { Location.count }.by(-2)
    end

    it "cascades destroy to productions and their shows" do
      production = create(:production, production_company: company)
      create(:show, production: production)
      create(:show, production: production)

      expect { company.destroy }.to change { Show.count }.by(-2)
    end
  end

  describe "with multiple productions" do
    it "can have multiple productions" do
      company = create(:production_company)
      production1 = create(:production, production_company: company, name: "Hamilton")
      production2 = create(:production, production_company: company, name: "Wicked")

      expect(company.productions).to include(production1, production2)
      expect(company.productions.count).to eq(2)
    end
  end

  describe "with users and roles" do
    it "can have multiple users through user_roles" do
      company = create(:production_company)
      user1 = create(:user)
      user2 = create(:user)

      create(:user_role, user: user1, production_company: company, role: "manager")
      create(:user_role, user: user2, production_company: company, role: "viewer")

      expect(company.users.reload).to include(user1, user2)
      expect(company.users.count).to eq(2)
    end
  end
end
