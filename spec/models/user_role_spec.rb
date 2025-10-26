require 'rails_helper'

RSpec.describe UserRole, type: :model do
  describe "associations" do
    it "belongs to user" do
      user_role = create(:user_role)
      expect(user_role.user).to be_present
      expect(user_role).to respond_to(:user)
    end

    it "belongs to production_company" do
      user_role = create(:user_role)
      expect(user_role.production_company).to be_present
      expect(user_role).to respond_to(:production_company)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      user_role = build(:user_role)
      expect(user_role).to be_valid
    end

    it "is invalid without a role" do
      user_role = build(:user_role, role: nil)
      expect(user_role).not_to be_valid
      expect(user_role.errors[:role]).to include("can't be blank")
    end

    it "only allows manager or viewer roles" do
      user_role = build(:user_role, role: "invalid_role")
      expect(user_role).not_to be_valid
      expect(user_role.errors[:role]).to include("is not included in the list")
    end

    it "allows manager role" do
      user_role = build(:user_role, :manager)
      expect(user_role).to be_valid
      expect(user_role.role).to eq("manager")
    end

    it "allows viewer role" do
      user_role = build(:user_role, role: "viewer")
      expect(user_role).to be_valid
    end

    it "validates uniqueness of user_id scoped to production_company_id" do
      user = create(:user)
      company = create(:production_company)
      create(:user_role, user: user, production_company: company)

      duplicate = build(:user_role, user: user, production_company: company)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include("has already been taken")
    end
  end

  describe "role assignment" do
    it "connects a user to a production company" do
      user_role = create(:user_role)

      expect(user_role.user).to be_present
      expect(user_role.production_company).to be_present
    end

    it "allows multiple users for one production company" do
      company = create(:production_company)
      user1 = create(:user)
      user2 = create(:user)

      create(:user_role, user: user1, production_company: company, role: "manager")
      create(:user_role, user: user2, production_company: company, role: "viewer")

      expect(company.users).to include(user1, user2)
    end

    it "allows one user to belong to multiple production companies" do
      user = create(:user)
      company1 = create(:production_company)
      company2 = create(:production_company)

      create(:user_role, user: user, production_company: company1, role: "manager")
      create(:user_role, user: user, production_company: company2, role: "viewer")

      expect(company1.users).to include(user)
      expect(company2.users).to include(user)
    end
  end
end
