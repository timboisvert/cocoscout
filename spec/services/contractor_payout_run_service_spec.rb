# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractorPayoutRunService do
  let(:org) { create(:organization, :pro) }
  let(:contractor) { create(:contractor, organization: org, stripe_account_id: "acct_c", payouts_enabled: true) }
  let(:contract) { create(:contract, organization: org, contractor: contractor) }
  let(:payment) { create(:contract_payment, :outgoing, contract: contract, amount: 300) }

  describe ".add_contract_payment!" do
    it "opens a contractor run with a per-contractor item + contribution and posts an earning" do
      result = nil
      expect { result = described_class.add_contract_payment!(payment) }.to change(PayoutBatch, :count).by(1)

      expect(result.added).to be(true)
      batch = result.batch
      expect(batch.kind).to eq("contractor")
      item = batch.items.find_by(payee: contractor)
      expect(item.amount_cents).to eq(30_000)
      expect(item.payout_contributions.first.source).to eq(payment)
      expect(org.payout_balance_cents_for(contractor)).to eq(30_000) # earned, awaiting payout
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

    it "rejects a contractor without a connected bank" do
      contractor.update!(payouts_enabled: false)
      expect(described_class.add_contract_payment!(payment).error).to match(/hasn't connected a bank/)
    end

    it "rejects a zero / TBD amount" do
      tbd = create(:contract_payment, :outgoing, :revenue_share_tbd, contract: contract)
      expect(described_class.add_contract_payment!(tbd).error).to match(/Set an amount/)
    end
  end

  it "marks the contract payment paid when the contractor run pays out" do
    allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_c"))
    batch = described_class.add_contract_payment!(payment).batch

    PayoutBatchService.process!(batch)

    expect(payment.reload).to be_status_paid
    expect(payment.payment_method).to eq("stripe")
    expect(org.payout_balance_cents_for(contractor)).to eq(0) # earned then paid
  end
end
