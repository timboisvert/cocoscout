# frozen_string_literal: true

require "rails_helper"

# Regression: contract activation created duplicate productions/shows when the
# activate endpoint was hit twice (double-submit / two endpoints). activate! must
# be idempotent and create exactly one production for the contract.
RSpec.describe "Contract#activate!", type: :model do
  let(:org) { create(:organization) }
  let(:location) { create(:location, organization: org) }
  let(:contract) do
    create(:contract,
           organization: org,
           status: :draft,
           production_name: "Contracted Show",
           contract_start_date: 1.week.from_now.to_date,
           contract_end_date: 2.weeks.from_now.to_date,
           draft_data: {
             "bookings" => [
               { "starts_at" => 1.week.from_now.change(hour: 19).iso8601, "duration" => "2", "location_id" => location.id }
             ]
           })
  end

  it "creates exactly one production" do
    expect { contract.activate! }.to change { contract.reload.production }.from(nil)
    expect(contract.production).to be_present
  end

  it "is idempotent — a second activate! creates no extra production/shows" do
    expect(contract.activate!).to be(true)

    expect { contract.activate! }.not_to change { Production.count }
    expect(contract.activate!).to be(false) # already active
    expect(contract.reload.production).to be_present
    expect(contract.space_rentals.count).to eq(1)
  end

  describe "linking to an existing production (Pattern 2)" do
    let!(:existing) { create(:production, organization: org, name: "My Existing Show") }
    let(:linked_contract) do
      create(:contract,
             organization: org,
             status: :draft,
             contract_start_date: 1.week.from_now.to_date,
             contract_end_date: 2.weeks.from_now.to_date,
             draft_data: {
               "link_production_id" => existing.id,
               "bookings" => [
                 { "starts_at" => 1.week.from_now.change(hour: 19).iso8601, "duration" => "2", "location_id" => location.id }
               ]
             })
    end

    it "reuses the linked production instead of creating a new one" do
      expect { linked_contract.activate! }.not_to change { Production.count }
      expect(linked_contract.reload.production).to eq(existing)
      expect(existing.reload.contracts).to contain_exactly(linked_contract)
    end

    it "keeps the linked production's original type (does not force third_party)" do
      linked_contract.activate!
      expect(existing.reload.production_type).to eq("in_house")
    end
  end
end
