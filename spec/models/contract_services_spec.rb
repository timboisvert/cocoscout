# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract services → payments", type: :model do
  let(:org) { create(:organization) }
  let(:location) { create(:location, organization: org) }

  it "generates a billable ContractPayment per service on activation" do
    contract = create(:contract, organization: org,
                                 contract_start_date: Date.current, contract_end_date: Date.current + 7.days,
                                 draft_data: {
                                   "bookings" => [
                                     { "location_id" => location.id, "starts_at" => 1.day.from_now.iso8601,
                                       "ends_at" => (1.day.from_now + 2.hours).iso8601 }
                                   ],
                                   "services" => [
                                     { "name" => "Technical services", "quantity" => 4, "unit_price" => 25.0,
                                       "unit" => "hourly", "direction" => "incoming" }
                                   ]
                                 })

    contract.activate!

    payment = contract.contract_payments.find_by(description: "Technical services")
    expect(payment).to be_present
    expect(payment.amount).to eq(100) # 4 hrs × $25
    expect(payment.direction).to eq("incoming")
  end

  it "skips services with no amount" do
    contract = create(:contract, organization: org,
                                 contract_start_date: Date.current, contract_end_date: Date.current + 7.days,
                                 draft_data: {
                                   "bookings" => [
                                     { "location_id" => location.id, "starts_at" => 1.day.from_now.iso8601,
                                       "ends_at" => (1.day.from_now + 2.hours).iso8601 }
                                   ],
                                   "services" => [ { "name" => "Freebie", "quantity" => 0, "unit_price" => 0 } ]
                                 })

    contract.activate!
    expect(contract.contract_payments.find_by(description: "Freebie")).to be_nil
  end
end

RSpec.describe "Contract cancel with payments referencing shows", type: :model do
  let(:org) { create(:organization) }
  let(:location) { create(:location, organization: org) }

  it "cancels and deletes events without tripping the contract_payments FK" do
    contract = create(:contract, :active, organization: org,
                                          contract_start_date: Date.current, contract_end_date: Date.current + 7.days)
    production = create(:production, organization: org, production_type: "third_party")
    contract.update!(production: production)
    show = create(:show, production: production)
    payment = create(:contract_payment, contract: contract, show: show, due_date: Date.current)

    expect { contract.cancel!(delete_events: true) }.not_to raise_error

    expect(Show.exists?(show.id)).to be(false)
    # The payment survives, just unlinked from the deleted show.
    expect(payment.reload.show_id).to be_nil
  end
end
