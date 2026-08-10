# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractorPayoutRunService do
  let(:org) { create(:organization, :pro) }
  let(:contractor) { create(:contractor, organization: org) }
  # The contractor is paid as its explicitly-linked Person (bank + ledger live there).
  let!(:payee) do
    create(:person, stripe_account_id: "acct_c", payouts_enabled: true).tap do |p|
      org.people << p
      contractor.update!(person: p)
    end
  end
  let(:contract) { create(:contract, organization: org, contractor: contractor) }
  let(:payment) { create(:contract_payment, :outgoing, contract: contract, amount: 300) }

  describe ".add_contract_payment!" do
    it "opens the performer run with a per-person item + contribution and posts an earning" do
      result = nil
      expect { result = described_class.add_contract_payment!(payment) }.to change(PayoutBatch, :count).by(1)

      expect(result.added).to be(true)
      batch = result.batch
      expect(batch.kind).to eq("performer") # contractors ride the performer run (one funding event)
      item = batch.items.find_by(payee: payee)
      expect(item.amount_cents).to eq(30_000)
      expect(item.payout_contributions.first.source).to eq(payment)
      expect(org.payout_balance_cents_for(payee)).to eq(30_000) # earned, awaiting payout
    end

    it "is idempotent per payment" do
      first = described_class.add_contract_payment!(payment)
      second = nil
      expect { second = described_class.add_contract_payment!(payment) }.not_to change(PayoutContribution, :count)
      expect(second.added).to be(false)
      expect(second.batch).to eq(first.batch)
    end

    it "rejects an incoming payment" do
      incoming = create(:contract_payment, contract: contract, amount: 100, direction: "incoming")
      expect(described_class.add_contract_payment!(incoming).added).to be(false)
    end

    it "rejects a contractor whose person hasn't connected a bank" do
      payee.update!(payouts_enabled: false)
      expect(described_class.add_contract_payment!(payment).error).to match(/hasn't connected a bank/)
    end

    it "rejects a contractor with no linked person yet" do
      unlinked = org.contractors.create!(name: "Unlinked Co")
      c = create(:contract, organization: org, contractor: unlinked)
      p = create(:contract_payment, :outgoing, contract: c, amount: 100)
      expect(described_class.add_contract_payment!(p).error).to match(/Link a person/)
    end

    it "rejects a zero / TBD amount" do
      tbd = create(:contract_payment, :outgoing, :revenue_share_tbd, contract: contract)
      expect(described_class.add_contract_payment!(tbd).error).to match(/Set an amount/)
    end
  end

  describe "paying the run" do
    before { allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_c")) }

    it "marks the contract payment paid and clears the person's balance" do
      batch = described_class.add_contract_payment!(payment).batch
      PayoutBatchService.process!(batch)

      expect(payment.reload).to be_status_paid
      expect(payment.payment_method).to eq("stripe")
      expect(org.payout_balance_cents_for(payee)).to eq(0) # earned then paid
    end

    it "does not charge the contractor as a $3 active performer" do
      batch = described_class.add_contract_payment!(payment).batch
      expect { PayoutBatchService.process!(batch) }.not_to change(PerformerActivation, :count)
    end
  end

  describe "services settled by payout deduction" do
    def deductible_service!(amount:, description: "Tech service")
      create(:contract_payment, contract: contract, direction: "incoming",
                                amount: amount, description: description,
                                settlement_method: "payout_deduction")
    end

    it "nets a smaller service out of the share as a visible negative line" do
      service = deductible_service!(amount: 100)

      batch = described_class.add_contract_payment!(payment).batch
      item = batch.items.find_by(payee: payee)

      # Gross share + itemized deduction, item pays the difference.
      expect(item.amount_cents).to eq(20_000)
      deduction = item.payout_contributions.find_by(source: service)
      expect(deduction.amount_cents).to eq(-10_000)
      expect(deduction.label).to include("Tech service").and include("deducted")

      # The service is settled — no pay link, nothing to chase.
      expect(service.reload).to be_status_paid
      expect(service.payment_method).to eq("payout_deduction")
      expect(service).not_to be_collectable_online

      # Ledger agrees with the run: they're owed the net.
      expect(org.payout_balance_cents_for(payee)).to eq(20_000)
    end

    it "pays out the net amount when the run runs" do
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_net"))
      deductible_service!(amount: 100)

      batch = described_class.add_contract_payment!(payment).batch
      PayoutBatchService.process!(batch)

      expect(Stripe::Transfer).to have_received(:create).with(hash_including(amount: 20_000), anything)
      expect(org.payout_balance_cents_for(payee)).to eq(0)
    end

    it "settles an exact offset as a wash — nothing rides the run, both sides paid" do
      service = deductible_service!(amount: 300) # equals the 300 share

      result = described_class.add_contract_payment!(payment)

      # Nothing to transfer, no item left, no dangling ledger.
      expect(result.batch.items.where(payee: payee)).to be_empty
      expect(org.payout_balance_cents_for(payee)).to eq(0)

      # BOTH payments are settled, so neither can be re-added or re-collected.
      expect(payment.reload).to be_status_paid
      expect(payment.payment_method).to eq("offset")
      expect(service.reload).to be_status_paid
      expect(service.payment_method).to eq("payout_deduction")
    end

    it "leaves the uncovered remainder payable directly when services exceed the share" do
      service = deductible_service!(amount: 450)

      described_class.add_contract_payment!(payment)

      # $300 share offsets $300 of the service; $150 flips back to payable.
      expect(payment.reload).to be_status_paid # settled by offset
      service.reload
      expect(service).to be_status_pending
      expect(service.amount.to_f).to eq(150.0)
      expect(service.settlement_method).to eq("direct")
      expect(service).to be_collectable_online
      expect(service.description).to include("offset against payout")
      expect(org.payout_balance_cents_for(payee)).to eq(0)
    end

    it "only deducts services due by the settling share's due date, never future events' fees" do
      # Per-event booth tech fees: this event's, and four future events'.
      current_fee = deductible_service!(amount: 50)
      current_fee.update!(due_date: payment.due_date)
      future_fees = [ 1, 2, 3, 4 ].map do |n|
        deductible_service!(amount: 50, description: "Booth Tech").tap do |s|
          s.update!(due_date: payment.due_date + n.months)
        end
      end

      batch = described_class.add_contract_payment!(payment).batch
      item = batch.items.find_by(payee: payee)

      # Only this event's fee comes out of this event's share.
      expect(item.payout_contributions.where("amount_cents < 0").count).to eq(1)
      expect(item.amount_cents).to eq(25_000)
      future_fees.each do |fee|
        expect(fee.reload).to be_status_pending
      end
    end

    it "sweeps in an earlier event's still-unpaid fee at the next settlement" do
      overdue_fee = deductible_service!(amount: 50)
      overdue_fee.update!(due_date: payment.due_date - 1.month)

      batch = described_class.add_contract_payment!(payment).batch
      item = batch.items.find_by(payee: payee)

      expect(item.amount_cents).to eq(25_000)
      expect(overdue_fee.reload).to be_status_paid
    end

    it "never deducts the same service twice across runs" do
      deductible_service!(amount: 100)
      described_class.add_contract_payment!(payment)

      second_outgoing = create(:contract_payment, :outgoing, contract: contract, amount: 200)
      batch = described_class.add_contract_payment!(second_outgoing).batch

      item = batch.items.find_by(payee: payee)
      # Second share rides untouched — the service settled on the first add.
      expect(item.payout_contributions.where("amount_cents < 0").count).to eq(1)
      expect(org.payout_balance_cents_for(payee)).to eq(20_000 + 20_000)
    end

    it "ignores direct-settlement and TBD services entirely" do
      create(:contract_payment, contract: contract, direction: "incoming", amount: 100,
                                settlement_method: "direct")
      create(:contract_payment, contract: contract, direction: "incoming", amount: 0,
                                amount_tbd: true, settlement_method: "payout_deduction")

      batch = described_class.add_contract_payment!(payment).batch
      item = batch.items.find_by(payee: payee)

      expect(item.amount_cents).to eq(30_000)
      expect(item.payout_contributions.where("amount_cents < 0")).to be_empty
    end
  end
end
