require 'rails_helper'

RSpec.describe Location, type: :model do
  let(:production_company) { create(:production_company) }

  describe "validations" do
    it "is valid with valid attributes" do
      location = build(:location, production_company: production_company)
      expect(location).to be_valid
    end

    it "is invalid without a name" do
      location = build(:location, name: nil, production_company: production_company)
      expect(location).not_to be_valid
      expect(location.errors[:name]).to include("can't be blank")
    end

    it "is invalid without an address1" do
      location = build(:location, address1: nil, production_company: production_company)
      expect(location).not_to be_valid
      expect(location.errors[:address1]).to include("can't be blank")
    end

    it "is invalid without a city" do
      location = build(:location, city: nil, production_company: production_company)
      expect(location).not_to be_valid
      expect(location.errors[:city]).to include("can't be blank")
    end

    it "is invalid without a state" do
      location = build(:location, state: nil, production_company: production_company)
      expect(location).not_to be_valid
      expect(location.errors[:state]).to include("can't be blank")
    end

    it "is invalid without a postal_code" do
      location = build(:location, postal_code: nil, production_company: production_company)
      expect(location).not_to be_valid
      expect(location.errors[:postal_code]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "belongs to a production_company" do
      location = create(:location)
      expect(location.production_company).to be_present
      expect(location).to respond_to(:production_company)
    end
  end

  describe "default location logic" do
    context "when creating the first location" do
      it "automatically sets it as default" do
        location = create(:location, production_company: production_company, default: false)
        expect(location.reload.default).to be true
      end
    end

    context "when creating a second location" do
      it "does not set it as default by default" do
        create(:location, production_company: production_company)
        second_location = create(:location, production_company: production_company, default: false)
        expect(second_location.default).to be false
      end
    end

    context "when setting a location as default" do
      it "unsets other default locations in the same production company" do
        first_location = create(:location, production_company: production_company)
        second_location = create(:location, production_company: production_company)

        expect(first_location.reload.default).to be true
        expect(second_location.reload.default).to be false

        second_location.update(default: true)

        expect(first_location.reload.default).to be false
        expect(second_location.reload.default).to be true
      end

      it "only affects locations in the same production company" do
        other_production_company = create(:production_company)
        first_location = create(:location, production_company: production_company)
        other_location = create(:location, production_company: other_production_company)

        expect(first_location.reload.default).to be true
        expect(other_location.reload.default).to be true
      end
    end

    context "when multiple locations exist" do
      it "ensures only one location is default per production company" do
        first_location = create(:location, production_company: production_company)
        second_location = create(:location, production_company: production_company)
        third_location = create(:location, production_company: production_company)

        second_location.update(default: true)

        expect(first_location.reload.default).to be false
        expect(second_location.reload.default).to be true
        expect(third_location.reload.default).to be false
      end
    end
  end
end
