# frozen_string_literal: true

require "rails_helper"

# The theater's CocoScout balance: ticket money waits on its show, becomes
# spendable the day after once the card money has settled, pays payout runs
# before the bank is debited, and can be withdrawn to the theater's bank.
RSpec.describe "Ticket money" do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro, stripe_account_id: "acct_theater", payouts_enabled: true) }
  let(:show_at) { Time.zone.local(2026, 10, 10, 19, 30) }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: show_at)) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  def sell(count, at: Time.zone.local(2026, 10, 1, 12))
    travel_to(at) do
      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
      TicketOrderSettlement.settle!(order)
      order.reload
    end
  end

  def summary
    TicketBalance.summary(org)
  end

  describe "the balance" do
    it "waits on the show, settles, then becomes spendable" do
      sell(5) # $100 for the theater; buyers pay the fees

      travel_to(Time.zone.local(2026, 10, 5, 12)) do
        expect(summary.to_h.slice(:upcoming_cents, :settling_cents, :available_cents))
          .to eq(upcoming_cents: 10_000, settling_cents: 0, available_cents: 0)
        expect(TicketMoneyRelease.due).to be_empty
      end

      # The day after the show it's released and recognized as income.
      travel_to(Time.zone.local(2026, 10, 11, 4)) do
        TicketMoneyReleaseJob.perform_now
        expect(listing.reload.released_at).to be_present
        expect(summary.available_cents).to eq(10_000)
        expect(ChartOfAccounts.account(org, :ticket_income).natural_balance_cents).to eq(10_000)
        expect(ChartOfAccounts.account(org, :advance_ticket_sales).natural_balance_cents).to eq(0)
        expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)

        # Released once, however often the job runs.
        expect(TicketMoneyRelease.release!(listing)).to be(false)
        expect(JournalEntry.live.where(source: listing, kind: "recognition").count).to eq(1)
      end
    end

    it "keeps sales still reaching the bank network out of reach for a couple of days" do
      sell(1, at: Time.zone.local(2026, 10, 10, 18))
      travel_to(Time.zone.local(2026, 10, 11, 4)) do
        TicketMoneyReleaseJob.perform_now
        expect(summary.to_h.slice(:settling_cents, :available_cents)).to eq(settling_cents: 2_000, available_cents: 0)
      end
      travel_to(Time.zone.local(2026, 10, 13, 4)) { expect(summary.available_cents).to eq(2_000) }
    end

    it "never releases a canceled show" do
      sell(2)
      listing.update!(status: "canceled")
      travel_to(Time.zone.local(2026, 10, 12)) do
        TicketMoneyReleaseJob.perform_now
        expect(listing.reload.released_at).to be_nil
      end
    end

    it "keeps money for upcoming shows out of every other draw on the org's money" do
      sell(5)
      travel_to(Time.zone.local(2026, 10, 5)) do
        expect(OrgCashEntry.balance_cents(org)).to eq(10_000)
        expect(OrgCashEntry.available_cents(org)).to eq(0)
      end
    end
  end

  describe "payout runs spend it first" do
    let(:payee) { create(:person, stripe_account_id: "acct_payee", payouts_enabled: true) }

    before do
      org.update!(stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account")
      sell(5)
      travel_to(Time.zone.local(2026, 10, 11, 4)) { TicketMoneyReleaseJob.perform_now }
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_1"))
    end

    def run_for(cents)
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: cents)
      PayoutBatchService.build_for(organization: org)
    end

    it "pays a run the balance covers today, with no bank debit" do
      allow(Stripe::PaymentIntent).to receive(:create)
      travel_to(Time.zone.local(2026, 10, 14, 10)) do
        batch = run_for(6_000)
        PayoutBatchService.fund!(batch)

        expect(Stripe::PaymentIntent).not_to have_received(:create)
        expect([ batch.reload.status, batch.balance_applied_cents ]).to eq([ "completed", 6_000 ])
        expect(summary.available_cents).to eq(4_000)
      end
    end

    it "debits the bank only for what the balance can't cover" do
      intent = double("pi", id: "pi_1", status: "processing", amount: 5_000)
      allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)
      travel_to(Time.zone.local(2026, 10, 14, 10)) do
        batch = run_for(15_000)
        PayoutBatchService.fund!(batch)

        expect(Stripe::PaymentIntent).to have_received(:create).with(hash_including(amount: 5_000), anything)
        expect(batch.reload.balance_applied_cents).to eq(10_000)
        expect(summary.available_cents).to eq(0)
      end
    end

    it "gives the balance back when the bank debit fails" do
      allow(Stripe::PaymentIntent).to receive(:create).and_raise(Stripe::StripeError.new("declined"))
      travel_to(Time.zone.local(2026, 10, 14, 10)) do
        batch = run_for(15_000)
        expect { PayoutBatchService.fund!(batch) }.to raise_error(PayoutBatchService::Error)
        expect([ batch.reload.status, batch.balance_applied_cents ]).to eq([ "failed", 0 ])
        expect(summary.available_cents).to eq(10_000)
      end
    end

    it "changes nothing for an org with no ticket money" do
      other = create(:organization, :pro, stripe_customer_id: "cus_2", funding_payment_method_id: "pm_2",
                                          funding_payment_method_type: "us_bank_account")
      PayoutLedgerEntry.post!(organization: other, payee: payee, entry_type: "earning", amount_cents: 3_000)
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_2", status: "processing", amount: 3_000))
      batch = PayoutBatchService.build_for(organization: other)
      PayoutBatchService.fund!(batch)

      expect(Stripe::PaymentIntent).to have_received(:create).with(hash_including(amount: 3_000), anything)
      expect(batch.reload.balance_applied_cents).to eq(0)
    end
  end

  describe "withdrawing" do
    before do
      sell(5)
      travel_to(Time.zone.local(2026, 10, 11, 4)) { TicketMoneyReleaseJob.perform_now }
    end

    it "sends spendable money to the theater's own bank" do
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_w"))
      travel_to(Time.zone.local(2026, 10, 14)) do
        withdrawal = BalanceWithdrawalService.withdraw!(org, amount_cents: 7_500)

        expect(Stripe::Transfer).to have_received(:create)
          .with(hash_including(amount: 7_500, destination: "acct_theater"), hash_including(idempotency_key: "balance-withdrawal-#{withdrawal.id}"))
        expect([ withdrawal.status, withdrawal.stripe_transfer_id ]).to eq([ "sent", "tr_w" ])
        expect(summary.available_cents).to eq(2_500)
        expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(7_500)
        expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
      end
    end

    it "won't take more than is available, or send anywhere without a connected bank" do
      travel_to(Time.zone.local(2026, 10, 14)) do
        expect { BalanceWithdrawalService.withdraw!(org, amount_cents: 10_001) }
          .to raise_error(BalanceWithdrawalService::Error, /Only \$100.00 is available/)
        org.update!(payouts_enabled: false)
        expect { BalanceWithdrawalService.withdraw!(org, amount_cents: 100) }
          .to raise_error(BalanceWithdrawalService::Error, /Connect your organization's bank/)
      end
    end

    it "puts the money back when Stripe can't send it" do
      allow(Stripe::Transfer).to receive(:create).and_raise(Stripe::StripeError.new("account closed"))
      travel_to(Time.zone.local(2026, 10, 14)) do
        expect { BalanceWithdrawalService.withdraw!(org, amount_cents: 5_000) }.to raise_error(BalanceWithdrawalService::Error)
        expect(org.balance_withdrawals.sole.status).to eq("failed")
        expect(summary.available_cents).to eq(10_000)
        expect(OrgCashEntry.balance_cents(org)).to eq(10_000)
      end
    end

    it "withdraws automatically only when the theater turned it on" do
      profile = TicketingProfile.for(org)
      profile.update!(enabled: true)
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_auto"))
      tuesday = Date.new(2026, 10, 13)
      monday = Date.new(2026, 10, 19)

      travel_to(monday) do
        BalanceAutoWithdrawJob.perform_now(monday)
        expect(org.balance_withdrawals).to be_empty

        profile.update!(auto_withdraw: "weekly")
        BalanceAutoWithdrawJob.perform_now(tuesday)
        expect(org.balance_withdrawals).to be_empty
        BalanceAutoWithdrawJob.perform_now(monday)
        expect(org.balance_withdrawals.sole.attributes.slice("amount_cents", "automatic")).to eq("amount_cents" => 10_000, "automatic" => true)
      end
    end

    it "tells the theater what its open payout run needs from the balance" do
      payee = create(:person, stripe_account_id: "acct_payee", payouts_enabled: true)
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: 4_200)
      PayoutBatchService.build_for(organization: org)
      expect(BalanceWithdrawalService.open_run_need_cents(org)).to eq(4_200)
    end
  end
end
