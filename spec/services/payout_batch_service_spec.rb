# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutBatchService do
  let(:org) { create(:organization, :pro) }

  # A payee with a connected bank and a positive balance.
  let(:ready) do
    p = create(:person, stripe_account_id: "acct_ready", payouts_enabled: true)
    PayoutLedgerEntry.post!(organization: org, payee: p, entry_type: "earning", amount_cents: 5000)
    p
  end

  # A payee owed money but who hasn't connected a bank yet.
  let(:not_connected) do
    p = create(:person)
    PayoutLedgerEntry.post!(organization: org, payee: p, entry_type: "earning", amount_cents: 3000)
    p
  end

  before { ready; not_connected }

  describe ".build_for" do
    it "includes only Connect-enabled payees with a positive balance" do
      batch = PayoutBatchService.build_for(organization: org)
      expect(batch.items.map(&:payee)).to eq([ ready ])
      expect(batch.items.first.amount_cents).to eq(5000)
      expect(batch.total_cents).to eq(5000)
    end
  end

  describe ".process!" do
    it "transfers each item, marks it paid, and debits the balance to zero" do
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_1"))

      batch = PayoutBatchService.build_for(organization: org)
      PayoutBatchService.process!(batch)

      item = batch.items.first
      expect(item.reload.status).to eq("paid")
      expect(item.stripe_transfer_id).to eq("tr_1")
      expect(batch.reload.status).to eq("completed")
      expect(org.payout_balance_cents_for(ready)).to eq(0)
      # The non-connected payee is untouched and still owed.
      expect(org.payout_balance_cents_for(not_connected)).to eq(3000)
    end

    it "leaves the balance intact when a transfer fails" do
      allow(Stripe::Transfer).to receive(:create).and_raise(Stripe::StripeError.new("no funds"))

      batch = PayoutBatchService.build_for(organization: org)
      PayoutBatchService.process!(batch)

      expect(batch.items.first.reload.status).to eq("failed")
      expect(batch.reload.status).to eq("failed")
      expect(org.payout_balance_cents_for(ready)).to eq(5000)
    end
  end

  describe ".fund!" do
    before { org.update!(stripe_customer_id: "cus_1") }

    it "card funding that succeeds immediately funds and processes the batch" do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded"))
      allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_1"))

      batch = PayoutBatchService.build_for(organization: org)
      PayoutBatchService.fund!(batch, method: "card")

      expect(batch.reload.status).to eq("completed")
      expect(batch.funding_status).to eq("succeeded")
      expect(org.payout_balance_cents_for(ready)).to eq(0)
    end

    it "ACH funding waits for settlement before transferring" do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_ach", status: "processing"))
      allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_2"))

      batch = PayoutBatchService.build_for(organization: org)
      PayoutBatchService.fund!(batch, method: "ach")

      # Not funded yet — balance intact proves no transfers ran.
      expect(batch.reload.status).to eq("funding")
      expect(batch.funding_status).to eq("processing")
      expect(org.payout_balance_cents_for(ready)).to eq(5000)

      # Settlement webhook advances it → transfers run and the balance clears.
      PayoutBatchService.advance_funding!(batch, "succeeded")
      expect(batch.reload.status).to eq("completed")
      expect(org.payout_balance_cents_for(ready)).to eq(0)
    end

    it "rejects an unknown funding method" do
      batch = PayoutBatchService.build_for(organization: org)
      expect { PayoutBatchService.fund!(batch, method: "crypto") }.to raise_error(ArgumentError)
    end
  end

  describe "reversal" do
    it "restores the balance when a paid item is marked failed" do
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_2"))
      batch = PayoutBatchService.build_for(organization: org)
      PayoutBatchService.process!(batch)
      expect(org.payout_balance_cents_for(ready)).to eq(0)

      batch.items.first.mark_failed!("Transfer reversed")
      expect(org.payout_balance_cents_for(ready)).to eq(5000)
    end
  end
end
