# frozen_string_literal: true

require "rails_helper"

# Moving a contract's date takes its per-event services along (they're keyed by
# when the date starts); before, the moved date lost them at the next
# amendment's Services step.
RSpec.describe "Moving a contract date keeps its services" do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:friday) { Time.zone.local(2026, 11, 6, 19) }
  let(:saturday) { Time.zone.local(2026, 11, 7, 19) }
  let(:booth) { org.house_services.create!(name: "Booth Tech") }
  let(:contract) do
    create(:contract, :active, organization: org, production: production, draft_data: {
      "services" => [ { "name" => "Booth Tech", "service_id" => booth.id, "per_event" => true, "unit" => "hourly", "unit_price" => 25.0,
                        "events" => [ { "starts_at" => friday.iso8601, "hours" => 2 }, { "starts_at" => saturday.iso8601, "hours" => 2 } ] } ],
      "amend" => { "services" => [ { "name" => "Booth Tech", "per_event" => true, "events" => [ { "starts_at" => friday.iso8601, "hours" => 3 } ] } ] }
    })
  end
  let(:rental) { create(:space_rental, contract: contract, starts_at: friday, ends_at: friday + 3.hours) }
  let!(:show) { create(:show, production: production, space_rental: rental, date_and_time: friday, duration_minutes: 120) }

  it "moves the date's service lines, staged amendment too, and leaves the other dates alone" do
    ContractDateChanges.move!(contract: contract, rental: rental, starts_at: friday + 7.days, ends_at: friday + 7.days + 3.hours)

    lines = contract.reload.draft_services.first["events"].map { |e| Time.zone.parse(e["starts_at"]) }
    expect(lines).to eq([ friday + 7.days, saturday ])
    expect(Time.zone.parse(contract.amend_data["services"].first["events"].first["starts_at"])).to eq(friday + 7.days)

    moved = show.reload
    expect(moved.date_and_time).to eq(friday + 7.days)
    expect(ShowServices.new([ moved ]).for(moved).map { |n| n.service.name }).to eq([ "Booth Tech" ])
  end
end
