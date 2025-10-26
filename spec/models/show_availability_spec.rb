require 'rails_helper'

RSpec.describe ShowAvailability, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      availability = build(:show_availability)
      expect(availability).to be_valid
    end

    it "validates uniqueness of person_id scoped to show_id" do
      person = create(:person)
      show = create(:show)
      create(:show_availability, person: person, show: show)

      duplicate = build(:show_availability, person: person, show: show)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:person_id]).to include("has already been taken")
    end

    it "allows the same person to have availabilities for different shows" do
      person = create(:person)
      show1 = create(:show)
      show2 = create(:show)

      create(:show_availability, person: person, show: show1)
      availability2 = build(:show_availability, person: person, show: show2)

      expect(availability2).to be_valid
    end
  end

  describe "associations" do
    it "belongs to person" do
      availability = create(:show_availability)
      expect(availability.person).to be_present
      expect(availability).to respond_to(:person)
    end

    it "belongs to show" do
      availability = create(:show_availability)
      expect(availability.show).to be_present
      expect(availability).to respond_to(:show)
    end
  end

  describe "status enum" do
    it "defaults to unset" do
      availability = create(:show_availability)
      expect(availability.status).to eq("unset")
      expect(availability.unset?).to be true
    end

    it "can be set to available" do
      availability = create(:show_availability, :available)
      expect(availability.status).to eq("available")
      expect(availability.available?).to be true
    end

    it "can be set to unavailable" do
      availability = create(:show_availability, :unavailable)
      expect(availability.status).to eq("unavailable")
      expect(availability.unavailable?).to be true
    end

    it "can transition between statuses" do
      availability = create(:show_availability)

      availability.available!
      expect(availability.available?).to be true

      availability.unavailable!
      expect(availability.unavailable?).to be true

      availability.unset!
      expect(availability.unset?).to be true
    end
  end

  describe "enum values" do
    it "maps unset to 0" do
      availability = create(:show_availability, status: :unset)
      expect(availability.status_before_type_cast).to eq(0)
    end

    it "maps available to 1" do
      availability = create(:show_availability, status: :available)
      expect(availability.status_before_type_cast).to eq(1)
    end

    it "maps unavailable to 2" do
      availability = create(:show_availability, status: :unavailable)
      expect(availability.status_before_type_cast).to eq(2)
    end
  end
end
