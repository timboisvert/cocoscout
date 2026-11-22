# frozen_string_literal: true

require "rails_helper"

# Balance first (Tim, 2026-11-22): a payout run pays everyone the CocoScout
# balance covers the moment it's submitted, in pay order, one whole payment
# each. The rest wait on the run while the balance grows (hourly), and the
# bank pays whoever is left on the run's deadline.
RSpec.describe "Balance-first payout runs" do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:org) do
    create(:organization, :pro, owner: owner, stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1",
                                funding_payment_method_type: "us_bank_account")
  end
  let(:staffer) { create(:person, name: "Sam Staff", stripe_account_id: "acct_s", payouts_enabled: true) }
  let(:big_performer) { create(:person, name: "Pat Performer", stripe_account_id: "acct_p", payouts_enabled: true) }
  let(:small_performer) { create(:person, name: "Quinn Performer", stripe_account_id: "acct_q", payouts_enabled: true) }
  let(:no_bank) { create(:person, name: "Nora Nobank") }
  let(:transfers) { [] }

  before do
    allow(Stripe::Transfer).to receive(:create) do |params, _opts|
      transfers << params
      Stripe::Transfer.construct_from(id: "tr_#{transfers.size}")
    end
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(double("pi", amount: 100_000, latest_charge: "py_fund"))
    # Ticket money on its way into the balance, so the rest wait the
    # organization's days (bank_due_at_for has its own examples below).
    allow(PayoutBatchService).to receive(:bank_due_at_for).and_wrap_original do |original, organization, **kw|
      organization.payout_waits_on_balance ? Time.current + organization.payout_bank_after_days.days : original.call(organization, **kw)
    end
  end

  after { clear_enqueued_jobs }

  def add_balance(cents)
    # Added from the bank three days ago: settled, spendable, and not a year
    # old (the 12-month rule would send that back on its own).
    OrgCashEntry.post!(organization: org, entry_type: "top_up", amount_cents: cents,
                       source: nil, description: "Added #{SecureRandom.hex(2)}", occurred_at: 3.days.ago)
  end

  def item_for(batch, payee, cents, category: "performer")
    item = batch.items.create!(payee: payee, amount_cents: cents, status: "pending")
    PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: payee, amount_cents: cents,
                               label: "Pay", category: category)
    item
  end

  let(:batch) do
    b = PayoutBatch.open_for(org, created_by: owner)
    item_for(b, staffer, 5_000, category: "staffing")
    item_for(b, big_performer, 3_000)
    item_for(b, small_performer, 2_000)
    b.recalculate_total!
    b
  end

  def paid_names(run)
    run.items.reload.select(&:paid?).map { |i| i.payee.name }.sort
  end

  it "pays staff first, then performers smallest first, skipping anyone who doesn't fit" do
    add_balance(6_000)
    PayoutBatchService.fund!(batch)

    batch.reload
    expect(paid_names(batch)).to eq([ "Sam Staff" ])
    expect(batch.items.where(paid_from_balance: true).count).to eq(1)
    expect(batch.status).to eq("funding")
    expect(batch.funding_status).to eq("awaiting_balance")
    expect(batch.bank_due_at).to be_within(1.minute).of(3.days.from_now)
    expect(batch.funding_payment_intent_id).to be_nil
    expect(transfers.map { |t| t[:destination] }).to eq([ "acct_s" ])
    expect(transfers.first).not_to have_key(:source_transaction)
    expect(CocoScoutBalance.available_cents(org)).to eq(1_000)
  end

  it "follows the run's own pay order, groups and people" do
    add_balance(6_000)
    batch.update!(pay_order: { "groups" => %w[performer staffing contractor], "payees" => [] })
    PayoutBatchService.fund!(batch)
    expect(paid_names(batch)).to eq([ "Pat Performer", "Quinn Performer" ])

    run = PayoutBatch.open_for(org, created_by: owner)
    item_for(run, big_performer, 900)
    item_for(run, small_performer, 800)
    run.recalculate_total!
    run.update!(pay_order: { "groups" => %w[performer], "payees" => [ "Person:#{big_performer.id}" ] })
    expect(PayoutPayOrder.sort(run, run.items.to_a).map { |i| i.payee.name }).to eq([ "Pat Performer", "Quinn Performer" ])
  end

  it "never spends the balance on someone without a bank, and tells only the people it paid" do
    add_balance(20_000)
    item_for(batch, no_bank, 1_000)
    batch.recalculate_total!

    PayoutBatchService.fund!(batch)
    batch.reload
    expect(batch.items.find_by(payee: no_bank).status).to eq("pending")
    expect(batch.items.find_by(payee: no_bank).paid_from_balance).to be(false)
    # Everyone with a bank is paid; the balance still covers Nora, so her money
    # is set aside on the run, which carries on as a funded run.
    expect(paid_names(batch)).to eq([ "Pat Performer", "Quinn Performer", "Sam Staff" ])
    expect(batch.status).to eq("partially_paid")
    expect(batch.funding_payment_intent_id).to be_nil
  end

  it "pays more each hour as the balance grows, and finishes without the bank" do
    add_balance(6_000)
    PayoutBatchService.fund!(batch)
    expect(paid_names(batch)).to eq([ "Sam Staff" ])

    add_balance(2_000)
    PayoutBalanceWavesJob.perform_now
    expect(paid_names(batch)).to eq([ "Quinn Performer", "Sam Staff" ])
    expect(batch.reload.funding_status).to eq("awaiting_balance")

    add_balance(5_000)
    PayoutBalanceWavesJob.perform_now
    batch.reload
    expect(batch.status).to eq("completed")
    expect(batch.items.all?(&:paid_from_balance)).to be(true)
    expect(Stripe::PaymentIntent).not_to have_received(:retrieve)
  end

  it "tells the managers when a morning pays more, with what happens to the rest" do
    owner_person = create(:person, name: "Olive Owner", user: owner, email: owner.email_address)
    org.update!(payout_notification_user_ids: [ owner.id ])
    add_balance(6_000)
    PayoutBatchService.fund!(batch)
    clear_enqueued_jobs

    add_balance(2_000)
    PayoutBalanceWavesJob.perform_now
    expect(enqueued_jobs.select { |j| j["job_class"] == "PayoutRunMorePaidNotificationJob" }.size).to eq(1)

    expect { perform_enqueued_jobs(only: PayoutRunMorePaidNotificationJob) }.to change(Notification, :count).by(1)
    notification = owner.notifications.last
    expect(notification.kind).to eq("payout_run_more_paid")
    expect(notification.title).to include("1 more payee")
    expect(owner_person).to be_present

    # A morning that finishes the run gets "everyone's paid" instead.
    clear_enqueued_jobs
    add_balance(3_000)
    PayoutBalanceWavesJob.perform_now
    expect(batch.reload.status).to eq("completed")
    expect(enqueued_jobs.map { |j| j["job_class"] }).not_to include("PayoutRunMorePaidNotificationJob")
  end

  it "has the bank pay whoever is left on the deadline, drawing only the run's own debit" do
    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_rest", status: "processing", amount: 4_000))
    add_balance(6_000)
    PayoutBatchService.fund!(batch)

    PayoutBalanceWavesJob.perform_now
    expect(Stripe::PaymentIntent).not_to have_received(:create)

    travel_to(4.days.from_now) { PayoutBalanceWavesJob.perform_now }
    # $50 rest, $10 still in the balance: the bank pays $40.
    expect(Stripe::PaymentIntent).to have_received(:create).with(hash_including(amount: 4_000), anything)
    batch.reload
    expect(batch.funding_status).to eq("processing")
    expect(batch.balance_applied_cents).to eq(1_000)

    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(double("pi", amount: 4_000, latest_charge: "py_rest"))
    PayoutBatchService.advance_funding!(batch, "succeeded", funded_cents: 4_000)
    batch.reload
    expect(batch.status).to eq("completed")
    # Sam was paid from the balance before the debit, so the debit's whole
    # $40 can carry Pat's $30; Quinn's $20 no longer fits and draws on the
    # $10 claimed from the balance plus the rest of the funded ledger.
    pinned = transfers.select { |t| t[:source_transaction] == "py_rest" }.map { |t| t[:destination] }
    expect(pinned).to eq([ "acct_p" ])
  end

  it "pays the rest from the bank at once when the organization doesn't wait on the balance" do
    org.update!(payout_waits_on_balance: false)
    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_now", status: "processing", amount: 4_000))
    add_balance(6_000)

    PayoutBatchService.fund!(batch)
    expect(paid_names(batch)).to eq([ "Sam Staff" ])
    expect(Stripe::PaymentIntent).to have_received(:create).with(hash_including(amount: 4_000), anything)
    expect(enqueued_jobs.select { |j| j["job_class"] == "PayoutRunSubmittedNotificationJob" }.map { |j| j["arguments"].last["from_balance"] }).to eq([ true ])
  end

  it "goes back to waiting on the balance when the rest's bank debit bounces, and says so truthfully" do
    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_rest", status: "processing", amount: 4_000))
    add_balance(6_000)
    PayoutBatchService.fund!(batch)
    PayoutBatchService.advance_from_balance!(batch.reload, bank: true)
    expect(batch.reload.funding_status).to eq("processing")

    PayoutBatchService.funding_failed!(batch, reason: "Insufficient funds")
    batch.reload
    expect(batch.status).to eq("funding")
    expect(batch.funding_status).to eq("awaiting_balance")
    expect(batch.funding_error).to eq("Insufficient funds")
    expect(paid_names(batch)).to eq([ "Sam Staff" ])

    expect(PayoutBatchService).to receive(:fund_rest!).never
    travel_to(4.days.from_now) { PayoutBalanceWavesJob.perform_now }
  end

  it "stays a draft, and says why, when the balance pays nobody and there's no bank to pay the rest" do
    org.update!(funding_payment_method_id: nil)
    add_balance(1_000)

    expect { PayoutBatchService.fund!(batch) }.to raise_error(PayoutBatchService::Error, /Connect a bank or card/)
    expect(batch.reload.status).to eq("draft")
    expect(transfers).to be_empty
  end

  it "keeps payees not yet paid from hearing their money is on its way" do
    add_balance(6_000)
    PayoutBatchService.fund!(batch)
    perform_enqueued_jobs(only: PayoutSentPayeeNotificationJob)

    notified = batch.items.reload.select(&:payee_notified_at).map { |i| i.payee.name }
    expect(notified).to eq([ "Sam Staff" ])
  end

  describe "when the bank pays the rest" do
    before { allow(PayoutBatchService).to receive(:bank_due_at_for).and_call_original }

    it "waits the organization's days only while money is on its way into the balance" do
      freeze_time do
        expect(PayoutBatchService.bank_due_at_for(org)).to eq(Time.current)

        OrgCashEntry.post!(organization: org, entry_type: "contract_payment", amount_cents: 2_000, source: nil,
                           description: "Contract payment", occurred_at: 1.hour.ago)
        expect(PayoutBatchService.bank_due_at_for(org)).to eq(3.days.from_now.in_time_zone(org.time_zone).beginning_of_day)

        org.update!(payout_waits_on_balance: false)
        expect(PayoutBatchService.bank_due_at_for(org)).to eq(Time.current)
      end
    end

    it "pays the rest from the bank at once when nothing is on its way" do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_now", status: "processing", amount: 4_000))
      add_balance(6_000)
      PayoutBatchService.fund!(batch)
      expect(paid_names(batch)).to eq([ "Sam Staff" ])
      expect(Stripe::PaymentIntent).to have_received(:create).with(hash_including(amount: 4_000), anything)
    end
  end

  it "keeps year-old money a waiting run needs, and sends back only the rest" do
    TicketingProfile.for(org).update!(enabled: true)
    org.update!(stripe_account_id: "acct_org", payouts_enabled: true)
    OrgCashEntry.post!(organization: org, entry_type: "opening_balance", amount_cents: 6_000, source: nil,
                       description: "Opening balance", occurred_at: 2.years.ago)
    PayoutBatchService.fund!(batch) # pays Sam $50; Pat and Quinn ($50) wait on the $10 left

    expect(BalanceWithdrawalService).not_to receive(:withdraw!)
    BalanceAutoWithdrawJob.perform_now

    OrgCashEntry.post!(organization: org, entry_type: "opening_balance", amount_cents: 9_000, source: nil,
                       description: "More opening balance", occurred_at: 2.years.ago)
    RSpec::Mocks.space.proxy_for(BalanceWithdrawalService).reset
    expect(BalanceWithdrawalService).to receive(:withdraw!).with(org, amount_cents: 5_000, automatic: true)
    BalanceAutoWithdrawJob.perform_now
  end

  it "holds automatic withdrawals while a run is paying from the balance" do
    TicketingProfile.for(org).update!(enabled: true, auto_withdraw: "after_shows")
    org.update!(stripe_account_id: "acct_org", payouts_enabled: true)
    add_balance(6_000)
    PayoutBatchService.fund!(batch)

    expect(BalanceWithdrawalService).not_to receive(:withdraw!)
    BalanceAutoWithdrawJob.perform_now
  end
end
