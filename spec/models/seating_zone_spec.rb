# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeatingZone, type: :model do
  let(:organization) { create(:organization) }
  let(:seating_configuration) { create(:seating_configuration, organization: organization) }

  describe "validations" do
    it "is valid with valid attributes" do
      zone = SeatingZone.new(
        seating_configuration: seating_configuration,
        name: "Front Row",
        zone_type: "individual_seats",
        unit_count: 11,
        capacity_per_unit: 1,
        position: 0
      )
      expect(zone).to be_valid
    end

    it "requires a name" do
      zone = SeatingZone.new(
        seating_configuration: seating_configuration,
        zone_type: "individual_seats",
        unit_count: 10,
        capacity_per_unit: 1
      )
      expect(zone).not_to be_valid
      expect(zone.errors[:name]).to include("can't be blank")
    end

    it "requires a zone_type" do
      zone = SeatingZone.new(
        seating_configuration: seating_configuration,
        name: "Test Zone",
        unit_count: 10,
        capacity_per_unit: 1
      )
      expect(zone).not_to be_valid
    end

    it "requires unit_count to be positive" do
      zone = SeatingZone.new(
        seating_configuration: seating_configuration,
        name: "Test Zone",
        zone_type: "tables",
        unit_count: 0,
        capacity_per_unit: 2
      )
      expect(zone).not_to be_valid
    end
  end

  describe "#calculate_total_capacity" do
    it "calculates total capacity before validation" do
      zone = SeatingZone.new(
        seating_configuration: seating_configuration,
        name: "Floor Tables",
        zone_type: "tables",
        unit_count: 4,
        capacity_per_unit: 2,
        position: 0
      )
      zone.valid?
      expect(zone.total_capacity).to eq(8)
    end

    it "calculates for rows correctly" do
      zone = SeatingZone.new(
        seating_configuration: seating_configuration,
        name: "Back Rows",
        zone_type: "rows",
        unit_count: 5,
        capacity_per_unit: 11,
        position: 0
      )
      zone.valid?
      expect(zone.total_capacity).to eq(55)
    end
  end

  describe "#formatted_summary" do
    it "formats individual seats correctly" do
      zone = SeatingZone.new(zone_type: "individual_seats", unit_count: 11, capacity_per_unit: 1)
      zone.valid?
      expect(zone.formatted_summary).to eq("11 seats")
    end

    it "formats tables correctly" do
      zone = SeatingZone.new(zone_type: "tables", unit_count: 4, capacity_per_unit: 2)
      zone.valid?
      expect(zone.formatted_summary).to eq("4 tables × 2 seats (8 total)")
    end

    it "formats rows correctly" do
      zone = SeatingZone.new(zone_type: "rows", unit_count: 5, capacity_per_unit: 11)
      zone.valid?
      expect(zone.formatted_summary).to eq("5 rows × 11 seats (55 total)")
    end

    it "formats booths correctly" do
      zone = SeatingZone.new(zone_type: "booths", unit_count: 3, capacity_per_unit: 4)
      zone.valid?
      expect(zone.formatted_summary).to eq("3 booths × 4 capacity (12 total)")
    end

    it "formats standing room correctly" do
      zone = SeatingZone.new(zone_type: "standing", unit_count: 50, capacity_per_unit: 1)
      zone.valid?
      expect(zone.formatted_summary).to eq("Standing room (50 capacity)")
    end
  end

  describe "#zone_type_label" do
    it "returns human-readable labels" do
      expect(SeatingZone.new(zone_type: "individual_seats").zone_type_label).to eq("Individual Seats")
      expect(SeatingZone.new(zone_type: "tables").zone_type_label).to eq("Tables")
      expect(SeatingZone.new(zone_type: "rows").zone_type_label).to eq("Rows of Seats")
      expect(SeatingZone.new(zone_type: "booths").zone_type_label).to eq("Booths / Private Areas")
      expect(SeatingZone.new(zone_type: "standing").zone_type_label).to eq("Standing Room")
    end
  end
end
