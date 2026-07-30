# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractBookingConflicts do
  let(:org) { create(:organization) }
  let(:location) { create(:location, organization: org) }
  let(:mainstage) { location.location_spaces.create!(name: "The Mainstage") }
  let(:existing_contract) { create(:contract, organization: org, production_name: "Resident Co") }

  let(:window) do
    { starts_at: Time.zone.parse("2026-08-07 18:00"), ends_at: Time.zone.parse("2026-08-07 22:00") }
  end

  # A new contract proposing a Mainstage booking that clashes in time.
  def contract_proposing_mainstage
    create(:contract, organization: org, production_name: "New Show",
      draft_data: { "bookings" => [ {
        "location_id" => location.id, "location_space_id" => mainstage.id,
        "starts_at" => "2026-08-07T18:00:00", "ends_at" => "2026-08-07T22:00:00"
      } ] })
  end

  it "flags a room booking against an existing ENTIRE-VENUE rental" do
    create(:space_rental, contract: existing_contract, location: location, location_space: nil, **window)

    service = described_class.new(contract_proposing_mainstage)

    expect(service.any?).to be(true)
    expect(service.count).to eq(1)
    day = service.conflict_days.first
    expect(day.space_name).to eq("The Mainstage")
    # The existing block names its own space so the producer sees it's a whole-venue hold.
    expect(day.conflicting_existing.map(&:sublabel)).to include("Entire Venue")
  end

  it "flags an ENTIRE-VENUE proposed booking against an existing room rental" do
    create(:space_rental, contract: existing_contract, location: location, location_space: mainstage, **window)

    whole_venue_contract = create(:contract, organization: org, production_name: "Takeover",
      draft_data: { "bookings" => [ {
        "location_id" => location.id, "location_space_id" => "",
        "starts_at" => "2026-08-07T18:00:00", "ends_at" => "2026-08-07T22:00:00"
      } ] })

    service = described_class.new(whole_venue_contract)

    expect(service.any?).to be(true)
    expect(service.conflict_days.first.space_name).to eq("Entire Venue")
  end

  it "does not flag when the existing booking is a different room" do
    rouge = location.location_spaces.create!(name: "The Rouge Room")
    create(:space_rental, contract: existing_contract, location: location, location_space: rouge, **window)

    expect(described_class.new(contract_proposing_mainstage).any?).to be(false)
  end

  it "does not flag against a cancelled contract's hold" do
    cancelled = create(:contract, :cancelled, organization: org)
    create(:space_rental, contract: cancelled, location: location, location_space: nil, allow_overlap: true, **window)

    expect(described_class.new(contract_proposing_mainstage).any?).to be(false)
  end
end
