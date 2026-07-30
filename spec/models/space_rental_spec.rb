# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpaceRental, type: :model do
  let(:organization) { create(:organization) }
  let(:location) { create(:location, organization: organization) }
  let(:contract) { create(:contract, organization: organization) }

  describe "#effective_event_starts_at" do
    let(:rental) { create(:space_rental, contract: contract, location: location, starts_at: Time.zone.parse("2025-01-15 17:00")) }

    context "when event_starts_at is not set" do
      it "returns starts_at" do
        expect(rental.effective_event_starts_at).to eq(rental.starts_at)
      end
    end

    context "when event_starts_at is set" do
      before { rental.update!(event_starts_at: Time.zone.parse("2025-01-15 19:00")) }

      it "returns event_starts_at" do
        expect(rental.effective_event_starts_at).to eq(Time.zone.parse("2025-01-15 19:00"))
      end
    end
  end

  describe "#effective_event_ends_at" do
    let(:rental) { create(:space_rental, contract: contract, location: location, starts_at: Time.zone.parse("2025-01-15 17:00"), ends_at: Time.zone.parse("2025-01-15 22:00")) }

    context "when event_ends_at is not set" do
      it "returns ends_at" do
        expect(rental.effective_event_ends_at).to eq(rental.ends_at)
      end
    end

    context "when event_ends_at is set" do
      before { rental.update!(event_ends_at: Time.zone.parse("2025-01-15 21:00")) }

      it "returns event_ends_at" do
        expect(rental.effective_event_ends_at).to eq(Time.zone.parse("2025-01-15 21:00"))
      end
    end
  end

  describe "#has_separate_event_time?" do
    let(:rental) { create(:space_rental, contract: contract, location: location, starts_at: Time.zone.parse("2025-01-15 17:00"), ends_at: Time.zone.parse("2025-01-15 22:00")) }

    context "when neither event time is set" do
      it "returns false" do
        expect(rental.has_separate_event_time?).to be false
      end
    end

    context "when event_starts_at equals starts_at" do
      before { rental.update!(event_starts_at: rental.starts_at) }

      it "returns false" do
        expect(rental.has_separate_event_time?).to be false
      end
    end

    context "when event_starts_at is different from starts_at" do
      before { rental.update!(event_starts_at: Time.zone.parse("2025-01-15 19:00")) }

      it "returns true" do
        expect(rental.has_separate_event_time?).to be true
      end
    end

    context "when event_ends_at is different from ends_at" do
      before { rental.update!(event_ends_at: Time.zone.parse("2025-01-15 21:00")) }

      it "returns true" do
        expect(rental.has_separate_event_time?).to be true
      end
    end

    context "when both event times match rental times" do
      before do
        rental.update!(
          event_starts_at: rental.starts_at,
          event_ends_at: rental.ends_at
        )
      end

      it "returns false" do
        expect(rental.has_separate_event_time?).to be false
      end
    end
  end

  describe "event time validations" do
    let(:rental) do
      create(:space_rental,
        contract: contract,
        location: location,
        starts_at: Time.zone.parse("2025-01-15 17:00"),
        ends_at: Time.zone.parse("2025-01-15 22:00")
      )
    end

    context "when event_starts_at is before rental starts_at" do
      it "is invalid" do
        rental.event_starts_at = Time.zone.parse("2025-01-15 16:00")
        expect(rental).not_to be_valid
        expect(rental.errors[:event_starts_at]).to include("cannot be before rental start time")
      end
    end

    context "when event_starts_at is after rental ends_at" do
      it "is invalid" do
        rental.event_starts_at = Time.zone.parse("2025-01-15 23:00")
        expect(rental).not_to be_valid
        expect(rental.errors[:event_starts_at]).to include("cannot be after rental end time")
      end
    end

    context "when event_ends_at is before rental starts_at" do
      it "is invalid" do
        rental.event_ends_at = Time.zone.parse("2025-01-15 16:00")
        expect(rental).not_to be_valid
        expect(rental.errors[:event_ends_at]).to include("cannot be before rental start time")
      end
    end

    context "when event_ends_at is after rental ends_at" do
      it "is invalid" do
        rental.event_ends_at = Time.zone.parse("2025-01-15 23:00")
        expect(rental).not_to be_valid
        expect(rental.errors[:event_ends_at]).to include("cannot be after rental end time")
      end
    end

    context "when event_ends_at is before event_starts_at" do
      it "is invalid" do
        rental.event_starts_at = Time.zone.parse("2025-01-15 20:00")
        rental.event_ends_at = Time.zone.parse("2025-01-15 19:00")
        expect(rental).not_to be_valid
        expect(rental.errors[:event_ends_at]).to include("must be after event start time")
      end
    end

    context "when event times are within rental period" do
      it "is valid" do
        rental.event_starts_at = Time.zone.parse("2025-01-15 18:00")
        rental.event_ends_at = Time.zone.parse("2025-01-15 21:00")
        expect(rental).to be_valid
      end
    end
  end

  describe "overlap validation with entire-venue bookings" do
    let(:mainstage) { location.location_spaces.create!(name: "The Mainstage") }
    let(:rouge) { location.location_spaces.create!(name: "The Rouge Room") }
    let(:other_contract) { create(:contract, organization: organization) }
    let(:window) do
      { starts_at: Time.zone.parse("2026-08-07 18:00"), ends_at: Time.zone.parse("2026-08-07 22:00") }
    end

    def new_rental(space, **attrs)
      SpaceRental.new(contract: contract, location: location, location_space: space, **window, **attrs)
    end

    it "blocks booking a room when the whole venue is already reserved" do
      create(:space_rental, contract: other_contract, location: location, location_space: nil, **window)

      rental = new_rental(mainstage)
      expect(rental).not_to be_valid
      expect(rental.errors[:base].join).to match(/overlaps with existing rentals/)
    end

    it "blocks booking the whole venue when a room is already reserved" do
      create(:space_rental, contract: other_contract, location: location, location_space: mainstage, **window)

      expect(new_rental(nil)).not_to be_valid
    end

    it "still blocks a double-booking of the same room" do
      create(:space_rental, contract: other_contract, location: location, location_space: mainstage, **window)

      expect(new_rental(mainstage)).not_to be_valid
    end

    it "allows two different rooms at the same time" do
      create(:space_rental, contract: other_contract, location: location, location_space: mainstage, **window)

      expect(new_rental(rouge)).to be_valid
    end

    it "does not conflict with a cancelled contract's entire-venue hold" do
      cancelled = create(:contract, :cancelled, organization: organization)
      create(:space_rental, contract: cancelled, location: location, location_space: nil, allow_overlap: true, **window)

      expect(new_rental(mainstage)).to be_valid
    end

    it "honors allow_overlap to schedule over the whole-venue hold anyway" do
      create(:space_rental, contract: other_contract, location: location, location_space: nil, **window)

      expect(new_rental(mainstage, allow_overlap: true)).to be_valid
    end
  end
end
