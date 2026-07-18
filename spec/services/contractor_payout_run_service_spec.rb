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
end
