# frozen_string_literal: true

require "rails_helper"

# The CocoScout balance's extras: what's safe to withdraw, adding money from
# the bank (and a refund waiting on it), and the 12-month rule.
RSpec.describe "Balance extras" do
  include ActiveJob::TestHelper

  let(:org) do
    create(:organization, :pro, stripe_account_id: "acct_sg", payouts_enabled: true,
                                stripe_customer_id: "cus_sg", funding_payment_method_id: "pm_sg", funding_payment_method_type: "card")
  end
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  before { TicketingProfile.for(org).update!(enabled: true) }

  def sell_and_release(count, paid_at: 10.days.ago)
    order = nil
    travel_to(paid_at) do
      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{SecureRandom.hex(3)}")
    end
    listing.update!(released_at: paid_at + 1.day)
    order.reload
  end

  describe "smart withdrawal" do
    it "keeps back what's coming due: the open run, money owed off-run, and contract payments due" do
      sell_and_release(10) # $200 available
      payee = create(:person, stripe_account_id: "acct_p", payouts_enabled: true)
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: 4_000)
      PayoutBatchService.build_for(organization: org) # $40 now staged on the open run
      other = create(:person)
      PayoutLedgerEntry.post!(organization: org, payee: other, entry_type: "earning", amount_cents: 2_500) # owed, can't be paid yet

      labels = BalanceObligations.items(org).to_h { |i| [ i.label, i.cents ] }
      expect(labels).to eq("Your open payout run" => 4_000, "Owed to performers and others, not yet on a run" => 2_500)
      expect(BalanceObligations.safe_to_withdraw_cents(org)).to eq(20_000 - 6_500)
    end

    it "doesn't keep back a contract payment that's already on a payout run" do
      sell_and_release(10)
      contract = create(:contract, organization: org)
      due = contract.contract_payments.create!(direction: "outgoing", amount: 2_000, due_date: 3.days.from_now, description: "Settlement")
      expect(BalanceObligations.items(org).to_h { |i| [ i.label, i.cents ] })
        .to include("Contract payments due in the next two weeks, not on a run yet" => 200_000)

      batch = org.payout_batches.create!(kind: "payout", status: "funding", trigger: "manual", funding_status: "processing", total_cents: 200_000)
      payee = create(:person)
      item = batch.items.create!(payee: payee, amount_cents: 200_000, status: "pending")
      PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: payee, source: due, amount_cents: 200_000, label: "Settlement")
      expect(BalanceObligations.items(org).map(&:label)).not_to include("Contract payments due in the next two weeks, not on a run yet")
    end

    it "prices approved staff hours the way payout runs do" do
      person = create(:person)
      create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2_000)
      create(:staff_time_entry, organization: org, person: person, started_at: 2.days.ago.change(hour: 18),
                                ended_at: 2.days.ago.change(hour: 21), approved_at: 1.day.ago)
      expect(BalanceObligations.items(org).find { |i| i.label.start_with?("Approved staff hours") }.cents).to eq(6_000)
    end
  end

  describe "adding funds" do
    it "lands at once by card and adds to what's available, in the books too" do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_top", status: "succeeded"))
      top_up = BalanceTopUpService.start!(org, amount_cents: 5_000)

      expect(Stripe::PaymentIntent).to have_received(:create).with(hash_including(amount: 5_000, metadata: hash_including(type: "balance_top_up")), anything)
      expect(top_up.reload.status).to eq("succeeded")
      expect(TicketBalance.available_cents(org)).to eq(5_000)
      expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(-5_000)
      expect(BooksReconciliation.check(org)).to eq([])

      BalanceTopUpService.settle!(top_up.reload) # the webhook arriving too
      expect(OrgCashEntry.where(source: top_up).count).to eq(1)
    end

    it "issues a refund waiting on a bank debit when the money lands" do
      order = sell_and_release(1)
      BalanceWithdrawal.create!(organization: org, amount_cents: 2_000, status: "sent") # the show's money is gone
      org.update!(funding_payment_method_type: "us_bank_account")
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_ach", status: "processing"))
      allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
      TicketingProfile.for(org).update!(refunds_after_show: true)

      top_up = BalanceTopUpService.start!(org, amount_cents: 2_092, refund_request: {
        "order_id" => order.id, "ticket_ids" => order.tickets.pluck(:id), "keep_fees" => false, "reason" => "Asked", "user_id" => nil
      })
      expect(top_up.status).to eq("pending")
      expect(order.reload.status).to eq("paid")

      BalanceTopUpService.settle!(top_up)
      expect(order.reload.status).to eq("refunded")
      expect(Stripe::Refund).to have_received(:create).with(hash_including(amount: 2_142), anything)
    end

    it "needs a funding source" do
      org.update!(funding_payment_method_id: nil)
      expect { BalanceTopUpService.start!(org, amount_cents: 100) }.to raise_error(BalanceTopUpService::Error, /Connect a bank or card/)
    end
  end

  describe "the 12-month rule" do
    it "sends money held over a year back to the bank, even with automatic withdrawal off" do
      sell_and_release(5, paid_at: 14.months.ago)
      sell_and_release(1, paid_at: 2.months.ago)
      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_aged"))

      expect(TicketBalance.aged_cents(org)).to eq(10_000)
      BalanceAutoWithdrawJob.perform_now
      expect(org.balance_withdrawals.sole.attributes.slice("amount_cents", "automatic")).to eq("amount_cents" => 10_000, "automatic" => true)
      expect(TicketBalance.available_cents(org)).to eq(2_000)
    end

    it "reminds a theater with no bank, once a month" do
      org.update!(payouts_enabled: false)
      sell_and_release(5, paid_at: 14.months.ago)
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs { 2.times { BalanceAutoWithdrawJob.perform_now } }
      expect(ActionMailer::Base.deliveries.map(&:subject).grep(/over a year/).size).to eq(TicketingNotifications.new(org).emails_for("withdrawal").size)
      expect(org.balance_withdrawals).to be_empty
    end
  end
end
