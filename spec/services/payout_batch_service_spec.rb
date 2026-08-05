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

    it "leaves the balance intact when a transfer fails, keeping the run open to retry" do
      allow(Stripe::Transfer).to receive(:create).and_raise(Stripe::StripeError.new("no funds"))

      batch = PayoutBatchService.build_for(organization: org)
      PayoutBatchService.process!(batch)

      expect(batch.items.first.reload.status).to eq("failed")
      # The run isn't a dead end: it stays partially_paid (retryable via
      # pay_remaining!) until every item is actually paid.
      expect(batch.reload.status).to eq("partially_paid")
      expect(batch.completed_at).to be_nil
      expect(org.payout_balance_cents_for(ready)).to eq(5000)

      # The retry path: Stripe recovers, pay_remaining! finishes the run.
      batch.update!(funding_status: "succeeded")
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_retry"))
      PayoutBatchService.pay_remaining!(batch)

      expect(batch.reload.status).to eq("completed")
      expect(org.payout_balance_cents_for(ready)).to eq(0)
    end

    it "settles every bundled show line with the shared transfer id (one item, many shows)" do
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_shared"))

      production = create(:production, organization: org)
      lines = 2.times.map do |i|
        show = create(:show, production: production, event_type: :show, date_and_time: (i + 2).days.ago)
        payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 25)
        line = ShowPayoutLineItem.create!(show_payout: payout, payee: ready, amount: 25)
        PerformerPayoutRunService.add_show_payout!(payout)
        line
      end

      batch = PayoutBatch.where(kind: "performer").order(:id).last
      PayoutBatchService.process!(batch)

      # Both lines share the one transfer's reference — no unique-index blowup.
      lines.each do |line|
        expect(line.reload.payout_reference_id).to eq("tr_shared")
        expect(line.paid?).to be(true)
      end
    end

    it "marks a performer a billable active performer for the payout's month when a performer run pays them" do
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_p"))

      batch = org.payout_batches.create!(kind: "performer", status: "draft", trigger: "manual")
      batch.items.create!(payee: ready, amount_cents: 5000, status: "pending")

      expect { PayoutBatchService.process!(batch) }
        .to change { PerformerActivation.for_month(Date.current).where(person: ready).count }.by(1)
    end

    it "does not create performer activations for a non-performer (balance) run" do
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_b"))

      batch = PayoutBatchService.build_for(organization: org) # kind: balance
      expect { PayoutBatchService.process!(batch) }.not_to change(PerformerActivation, :count)
    end
  end

  describe ".fund!" do
    before { org.update!(stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account") }

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

    it "promises the payee nothing while an ACH debit is still settling" do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_n", status: "processing"))

      batch = PayoutBatchService.build_for(organization: org)

      # Submitted, not settled: the debit can still bounce, so nobody is told
      # money is coming yet.
      expect { PayoutBatchService.fund!(batch, method: "ach") }
        .not_to have_enqueued_job(PayoutSentPayeeNotificationJob)

      # The settlement webhook is what actually sends the money — and the notice.
      allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_ach"))
      expect { PayoutBatchService.advance_funding!(batch, "succeeded") }
        .to have_enqueued_job(PayoutSentPayeeNotificationJob).with(batch.id)
    end

    it "promises nobody anything when the funding debit fails" do
      allow(Stripe::PaymentIntent).to receive(:create).and_raise(Stripe::StripeError.new("card declined"))

      batch = PayoutBatchService.build_for(organization: org)

      expect {
        expect { PayoutBatchService.fund!(batch, method: "ach") }.to raise_error(PayoutBatchService::Error)
      }.not_to have_enqueued_job(PayoutSentPayeeNotificationJob)
    end

    it "notifies immediately for card funding, which sends in the same breath" do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_c", status: "succeeded"))
      allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_c"))

      batch = PayoutBatchService.build_for(organization: org)

      expect { PayoutBatchService.fund!(batch, method: "card") }
        .to have_enqueued_job(PayoutSentPayeeNotificationJob).with(batch.id)
    end

    it "raises when the org has no connected funding source" do
      org.update!(funding_payment_method_id: nil)
      batch = PayoutBatchService.build_for(organization: org)
      expect { PayoutBatchService.fund!(batch, method: "ach") }
        .to raise_error(PayoutBatchService::Error, /Connect a bank or card/)
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
