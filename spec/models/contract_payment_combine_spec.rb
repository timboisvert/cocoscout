# frozen_string_literal: true

require "rails_helper"

# Several small invoices on different days — rehearsal rent, a booth tech, the
# event itself — can be folded by hand into ONE payment the payer owes: one
# amount, one pay link, one row on their side. And folded back out again.
RSpec.describe "Combining contract payments", type: :model do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:contract) { create(:contract, :active, organization: org) }

  let!(:event_payment) do
    create(:contract_payment, contract: contract, description: "Event fee",
                              amount: 600.0, due_date: Date.new(2026, 10, 19))
  end
  let!(:rehearsal_one) do
    create(:contract_payment, contract: contract, description: "Rehearsal — Sep 10, 2026",
                              amount: 100.0, due_date: Date.new(2026, 9, 10))
  end
  let!(:rehearsal_two) do
    create(:contract_payment, contract: contract, description: "Rehearsal — Sep 17, 2026",
                              amount: 100.0, due_date: Date.new(2026, 9, 17))
  end

  describe "#merge_in!" do
    it "folds the others into one payment: $600 + $100 + $100 is one $800 row due on the host's date" do
      event_payment.merge_in!([ rehearsal_one, rehearsal_two ])

      expect(contract.contract_payments.count).to eq(1)
      expect(event_payment.reload.amount.to_f).to eq(800.0)
      expect(event_payment.due_date).to eq(Date.new(2026, 10, 19))
      expect(event_payment.base_amount).to eq(600.0)
      expect(event_payment.combined?).to be(true)
      expect(event_payment.merged_components.map { |c| [ c["name"], c["amount"].to_f, c["billed_for"] ] })
        .to contain_exactly([ "Rehearsal — Sep 10, 2026", 100.0, "2026-09-10" ],
                            [ "Rehearsal — Sep 17, 2026", 100.0, "2026-09-17" ])
      expect(event_payment.folded_services_summary)
        .to eq("incl. Rehearsal — Sep 10, 2026 $100.00 and Rehearsal — Sep 17, 2026 $100.00")
    end

    it "leaves the payer exactly one payment to collect" do
      event_payment.merge_in!([ rehearsal_one, rehearsal_two ])
      expect(contract.contract_payments.select(&:collectable_online?).size).to eq(1)
    end

    it "hoists a folded service intact — name and billed_for survive, so an amendment can still unfold it" do
      rehearsal_one.fold_service!(name: "Booth Tech", amount: 25.0, billed_for: Date.new(2026, 9, 10))

      event_payment.merge_in!([ rehearsal_one ])

      expect(event_payment.reload.amount.to_f).to eq(725.0)
      expect(event_payment.service_components)
        .to eq([ { "kind" => "service", "name" => "Booth Tech", "amount" => 25.0, "billed_for" => "2026-09-10" } ])
      # The merged component remembers only the rehearsal's own amount.
      expect(event_payment.merged_components.sole["amount"].to_f).to eq(100.0)
    end

    it "refuses money anyone has touched" do
      paid = create(:contract_payment, :paid, contract: contract, amount: 50.0)
      tbd = create(:contract_payment, contract: contract, amount: 0, amount_tbd: true)
      deducted = create(:contract_payment, contract: contract, amount: 50.0, settlement_method: "payout_deduction")
      outgoing = create(:contract_payment, contract: contract, amount: 50.0, direction: "outgoing")
      in_checkout = create(:contract_payment, contract: contract, amount: 50.0, stripe_checkout_session_id: "cs_123")
      other_contract = create(:contract_payment, amount: 50.0)

      [ paid, tbd, deducted, outgoing, in_checkout, other_contract ].each do |payment|
        expect { event_payment.merge_in!([ payment ]) }.to raise_error(ArgumentError)
      end
      expect { paid.merge_in!([ rehearsal_one ]) }.to raise_error(ArgumentError, /can't be combined/)
      expect { event_payment.merge_in!([]) }.to raise_error(ArgumentError, /nothing to combine/)
      expect(event_payment.reload.amount.to_f).to eq(600.0)
      expect(contract.contract_payments.status_pending.count).to eq(7)
    end
  end

  describe "#split_merged!" do
    it "puts everything back: own rows, own due dates, own services, and the host shrinks to its own amount" do
      rehearsal_one.fold_service!(name: "Booth Tech", amount: 25.0, billed_for: Date.new(2026, 9, 10))
      event_payment.merge_in!([ rehearsal_one, rehearsal_two ])

      event_payment.split_merged!

      expect(event_payment.reload.amount.to_f).to eq(600.0)
      expect(event_payment.combined?).to be(false)
      expect(event_payment.components).to eq([])

      rows = contract.contract_payments.status_pending.by_due_date.where.not(id: event_payment.id)
      expect(rows.map { |p| [ p.description, p.amount.to_f, p.due_date ] })
        .to eq([ [ "Rehearsal — Sep 10, 2026", 125.0, Date.new(2026, 9, 10) ],
                 [ "Rehearsal — Sep 17, 2026", 100.0, Date.new(2026, 9, 17) ] ])
      expect(rows.first.folded_services_summary).to eq("incl. Booth Tech $25.00")
    end

    it "refuses when there's nothing combined, or the money is spoken for" do
      expect { event_payment.split_merged! }.to raise_error(ArgumentError, /no combined payments/)

      event_payment.merge_in!([ rehearsal_one ])
      event_payment.update!(stripe_checkout_session_id: "cs_live")
      expect { event_payment.split_merged! }.to raise_error(ArgumentError, /can't be split/)
    end
  end

  describe "#display_name and #breakdown_items" do
    it "dates a bare description so it stands on its own, and leaves already-dated ones alone" do
      expect(event_payment.display_name).to eq("Event fee — Oct 19, 2026")
      expect(rehearsal_one.display_name).to eq("Rehearsal — Sep 10, 2026")
    end

    it "itemizes what a combined payment covers, own fee first" do
      rehearsal_one.fold_service!(name: "Booth Tech", amount: 25.0, billed_for: Date.new(2026, 9, 10))
      event_payment.merge_in!([ rehearsal_one, rehearsal_two ])

      expect(event_payment.breakdown_items).to eq([
        [ "Event fee — Oct 19, 2026", 600.0 ],
        [ "Booth Tech — Sep 10, 2026", 25.0 ],
        [ "Rehearsal — Sep 10, 2026", 100.0 ],
        [ "Rehearsal — Sep 17, 2026", 100.0 ]
      ])
    end

    it "has no breakdown for a plain payment" do
      expect(event_payment.breakdown_items).to eq([])
    end
  end

  describe "amendments" do
    it "never mints a fresh row for a slot living inside a combined payment" do
      event_payment.merge_in!([ rehearsal_one, rehearsal_two ])

      contract.reconcile_amended_payments!([
        { "description" => "Event fee", "due_date" => "2026-10-19", "direction" => "incoming", "amount" => 600.0 },
        { "description" => "Rehearsal — Sep 10, 2026", "due_date" => "2026-09-10", "direction" => "incoming", "amount" => 100.0 },
        { "description" => "Rehearsal — Sep 17, 2026", "due_date" => "2026-09-17", "direction" => "incoming", "amount" => 100.0 }
      ])

      expect(contract.contract_payments.count).to eq(1)
      expect(event_payment.reload.amount.to_f).to eq(800.0)
    end

    it "keeps the combined money riding on top when the deal re-prices the host" do
      event_payment.merge_in!([ rehearsal_one, rehearsal_two ])

      contract.reconcile_amended_payments!([
        { "description" => "Event fee", "due_date" => "2026-10-19", "direction" => "incoming", "amount" => 650.0 }
      ])

      expect(event_payment.reload.amount.to_f).to eq(850.0)
      expect(event_payment.base_amount).to eq(650.0)
    end
  end
end
