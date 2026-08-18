# frozen_string_literal: true

require "rails_helper"

# A service they pay us for on an event is part of THAT event's payment — one
# amount, one pay link — never a second invoice beside it.
RSpec.describe "Contract services fold into the event's payment", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:location) { create(:location, organization: org) }
  let(:oct10) { Time.zone.parse("2026-10-10 19:00") }
  let(:oct17) { Time.zone.parse("2026-10-17 19:00") }

  def build_contract(services:, payments: nil, bookings: nil)
    bookings ||= [ oct10, oct17 ].map { |t| { "location_id" => location.id, "starts_at" => t.iso8601, "ends_at" => (t + 3.hours).iso8601 } }
    payments ||= [ oct10, oct17 ].map { |t| { "description" => "#{t.strftime('%b %-d')} event", "amount" => 350.0, "direction" => "incoming", "due_date" => t.to_date.to_s } }
    create(:contract, organization: org,
                      contract_start_date: oct10.to_date, contract_end_date: oct17.to_date,
                      draft_data: { "bookings" => bookings, "payments" => payments, "services" => services,
                                    "payment_structure" => "per_event" })
  end

  let(:booth_tech) do
    { "name" => "Booth Tech", "unit" => "flat", "unit_price" => 50.0, "direction" => "incoming",
      "settlement" => "direct", "per_event" => true,
      "events" => [ { "starts_at" => oct10.iso8601 } ] }
  end

  it "bills a per-event service INSIDE the event's payment: $350 rent + $50 booth tech is one $400 payment" do
    contract = build_contract(services: [ booth_tech ])
    contract.activate!

    payments = contract.contract_payments.status_pending.by_due_date.to_a
    expect(payments.map { |p| [ p.description, p.amount.to_f ] }).to eq([ [ "Oct 10 event", 400.0 ], [ "Oct 17 event", 350.0 ] ])
    oct10_payment = payments.first
    expect(oct10_payment.includes_services?).to be(true)
    expect(oct10_payment.base_amount).to eq(350.0)
    expect(oct10_payment.components_total).to eq(50.0)
    expect(oct10_payment.folded_services_summary).to eq("incl. Booth Tech $50.00")
    expect(contract.contract_payments.where("description LIKE 'Booth Tech%'")).to be_empty
  end

  it "treats 'taken out of their payout' as a direct charge on a deal where they pay us — there's no payout to take it from" do
    contract = build_contract(services: [ booth_tech.merge("settlement" => "payout_deduction") ])
    contract.activate!

    payment = contract.contract_payments.find_by(description: "Oct 10 event")
    expect(payment.amount.to_f).to eq(400.0)
    expect(payment.folded_services_summary).to eq("incl. Booth Tech $50.00")
    expect(contract.contract_payments.where("description LIKE 'Booth Tech%'")).to be_empty
    expect(contract.can_net_services_from_payout?).to be(false)
  end

  it "keeps a real deduction as its own row when the deal pays them (it nets against that payout)" do
    outgoing = [ { "description" => "Oct 10 settlement", "amount" => 500.0, "direction" => "outgoing", "due_date" => oct10.to_date.to_s } ]
    contract = build_contract(services: [ booth_tech.merge("settlement" => "payout_deduction") ], payments: outgoing)
    contract.activate!

    expect(contract.can_net_services_from_payout?).to be(true)
    expect(contract.contract_payments.find_by(description: "Oct 10 settlement").amount.to_f).to eq(500.0)
    deduction = contract.contract_payments.find_by(description: "Booth Tech — Oct 10, 2026")
    expect(deduction).to be_present
    expect(deduction.deduct_from_payout?).to be(true)
  end

  it "folds a once-per-contract service into the last payment on the schedule" do
    flat = { "name" => "Cleaning", "unit" => "flat", "quantity" => 1, "unit_price" => 75.0, "direction" => "incoming" }
    contract = build_contract(services: [ flat ])
    contract.activate!

    expect(contract.contract_payments.find_by(description: "Oct 17 event").amount.to_f).to eq(425.0)
    expect(contract.contract_payments.find_by(description: "Cleaning")).to be_nil
  end

  it "stands alone only when there is no payment of the deal to fold into" do
    contract = build_contract(services: [ booth_tech ], payments: [])
    contract.activate!

    expect(contract.contract_payments.find_by(description: "Booth Tech — Oct 10, 2026").amount.to_f).to eq(50.0)
  end

  it "unfolds and re-bills on an amendment, and never bills twice" do
    contract = build_contract(services: [ booth_tech ])
    contract.activate!
    contract.reload

    contract.reconcile_service_payments!([ booth_tech.merge("unit_price" => 80.0) ])
    payment = contract.contract_payments.find_by(description: "Oct 10 event")
    expect(payment.amount.to_f).to eq(430.0)
    expect(payment.service_components.map { |c| c["amount"] }).to eq([ 80.0 ])

    contract.reconcile_service_payments!([])
    expect(payment.reload.amount.to_f).to eq(350.0)
    expect(payment.includes_services?).to be(false)
  end

  it "keeps folded services when an amendment re-prices the event's payment" do
    contract = build_contract(services: [ booth_tech ])
    contract.activate!
    contract.reload

    contract.reconcile_amended_payments!([
      { "description" => "Oct 10 event", "amount" => 400.0, "direction" => "incoming", "due_date" => oct10.to_date.to_s },
      { "description" => "Oct 17 event", "amount" => 350.0, "direction" => "incoming", "due_date" => oct17.to_date.to_s }
    ])

    payment = contract.contract_payments.find_by(description: "Oct 10 event")
    expect(payment.amount.to_f).to eq(450.0) # $400 rent + the $50 booth tech still inside it
    expect(payment.folded_services_summary).to eq("incl. Booth Tech $50.00")
  end

  describe ServicePaymentFoldBackfill do
    it "folds already-split service rows into their event's payment, once, and reports it" do
      contract = build_contract(services: [ booth_tech ])
      contract.activate!
      # Undo the fold to recreate the old shape: two rows for one night.
      payment = contract.contract_payments.find_by(description: "Oct 10 event")
      payment.update!(amount: 350.0, components: [])
      contract.contract_payments.create!(description: "Booth Tech — Oct 10, 2026", amount: 50.0, direction: "incoming",
                                         settlement_method: "direct", due_date: oct10.to_date, show_id: payment.show_id)

      dry = described_class.run(dry_run: true, contract_ids: [ contract.id ])
      expect(dry.folded).to eq(1)
      expect(contract.contract_payments.count).to eq(3)

      result = described_class.run(contract_ids: [ contract.id ])
      expect(result.folded).to eq(1)
      expect(contract.contract_payments.count).to eq(2)
      expect(payment.reload.amount.to_f).to eq(400.0)
      expect(payment.folded_services_summary).to eq("incl. Booth Tech $50.00")

      expect(described_class.run(contract_ids: [ contract.id ]).folded).to eq(0)
    end

    it "folds a stored 'payout deduction' row that has no payout to net against (a they-pay-us deal)" do
      contract = build_contract(services: [ booth_tech.merge("settlement" => "payout_deduction") ])
      contract.activate!
      # Recreate the old shape: the deduction row billed beside the rent.
      payment = contract.contract_payments.find_by(description: "Oct 10 event")
      payment.update!(amount: 350.0, components: [])
      contract.contract_payments.create!(description: "Booth Tech — Oct 10, 2026", amount: 50.0, direction: "incoming",
                                         settlement_method: "payout_deduction", due_date: oct10.to_date, show_id: payment.show_id)

      result = described_class.run(contract_ids: [ contract.id ])
      expect(result.folded).to eq(1)
      expect(payment.reload.amount.to_f).to eq(400.0)
      expect(contract.contract_payments.count).to eq(2)
    end

    it "leaves a real deduction (a deal that pays them) alone" do
      outgoing = [ { "description" => "Oct 10 settlement", "amount" => 500.0, "direction" => "outgoing", "due_date" => oct10.to_date.to_s } ]
      contract = build_contract(services: [ booth_tech.merge("settlement" => "payout_deduction") ], payments: outgoing)
      contract.activate!
      result = described_class.run(contract_ids: [ contract.id ])
      expect(result.folded).to eq(0)
      expect(contract.contract_payments.count).to eq(2)
    end
  end
end
