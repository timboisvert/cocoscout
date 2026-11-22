# frozen_string_literal: true

require "rails_helper"

# The pages for balance-first payout runs (Tim, 2026-11-22): a short box with
# Pay now and Manage payout priority, the Pay order window, the waiting run's
# Pay the rest from my bank, and Money settings → Payout runs.
RSpec.describe "Manage balance-first payout runs", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) do
    create(:organization, :pro, owner: owner, stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1",
                                funding_payment_method_type: "us_bank_account")
  end
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:staffer) { create(:person, name: "Sam Staff", stripe_account_id: "acct_s", payouts_enabled: true) }
  let(:performer) { create(:person, name: "Pat Performer", stripe_account_id: "acct_p", payouts_enabled: true) }

  let!(:batch) do
    b = PayoutBatch.open_for(org, created_by: owner)
    [ [ staffer, 5_000, "staffing" ], [ performer, 3_000, "performer" ] ].each do |payee, cents, category|
      item = b.items.create!(payee: payee, amount_cents: cents, status: "pending")
      PayoutContribution.create!(payout_batch: b, payout_batch_item: item, payee: payee, amount_cents: cents, label: "Pay", category: category)
    end
    b.recalculate_total!
    b
  end

  before do
    allow(Stripe::Transfer).to receive(:create).and_return(Stripe::Transfer.construct_from(id: "tr_1"))
    # Ticket money on its way into the balance: the rest wait three days.
    allow(PayoutBatchService).to receive(:bank_due_at_for) { Time.current + 3.days }
    OrgCashEntry.post!(organization: org, entry_type: "top_up", amount_cents: 6_000, source: nil, description: "Added", occurred_at: 3.days.ago)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "says in one line who the balance pays today and when the rest are paid" do
    get manage_payout_batch_path(batch)
    expect(response.body).to include("Ready to pay 2 payees · $80.00")
    due = 3.days.from_now.in_time_zone(org.time_zone).strftime("%B %-d")
    expect(response.body).to include("1 payee is paid today from your CocoScout balance. The other 1 ($30.00) is paid as ticket money clears, or from your bank on #{due}.")
    expect(response.body).to include("Pay now", "Manage payout priority", "Payout priority")
    expect(response.body).not_to include("We debit your bank via ACH")
  end

  it "saves the run's own pay order, and goes back to the default" do
    patch manage_pay_order_payout_batch_path(batch),
          params: { groups: %w[performer staffing contractor], payees: [ "Person:#{performer.id}", "Person:#{staffer.id}", "Person:999" ] }
    expect(response).to redirect_to(manage_payout_batch_path(batch))
    expect(batch.reload.pay_order).to eq("groups" => %w[performer staffing contractor],
                                         "payees" => [ "Person:#{performer.id}", "Person:#{staffer.id}" ])

    get manage_payout_batch_path(batch)
    expect(response.body).to include("1 payee is paid today from your CocoScout balance. The other 1 ($50.00)")

    patch manage_pay_order_payout_batch_path(batch), params: { reset: "1" }
    expect(batch.reload.pay_order).to eq({})
  end

  it "shows a waiting run, and has the bank pay the rest on request" do
    post manage_fund_payout_batch_path(batch)
    expect(flash[:notice]).to start_with("Paid 1 payee from your CocoScout balance. The other 1 is paid as ticket money clears")

    get manage_payout_batch_path(batch)
    expect(response.body).to include("Paying from your balance", "$30.00 still to pay on this run", "Pay the rest from my bank")
    # Nothing more is on its way, so waiting wouldn't change what the bank pays.
    expect(response.body).to include("No more ticket money clears before the bank debit on #{3.days.from_now.in_time_zone(org.time_zone).strftime('%A, %B %-d')}, so waiting won&#39;t make it smaller.",
                                     "See each day", "If you wait", "Bank debit scheduled")

    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_rest", status: "processing", amount: 2_000))
    post manage_pay_rest_payout_batch_path(batch)
    expect(Stripe::PaymentIntent).to have_received(:create).with(hash_including(amount: 2_000), anything)
    expect(batch.reload.funding_status).to eq("processing")
    expect(flash[:notice]).to eq("Paid 1 payee from your CocoScout balance. The rest are paid when your bank debit clears.")
  end

  it "moves a waiting run's scheduled bank debit, within two weeks" do
    post manage_fund_payout_batch_path(batch)
    zone = ActiveSupport::TimeZone[org.time_zone]
    day = Time.current.in_time_zone(zone).to_date + 5
    patch manage_bank_day_payout_batch_path(batch), params: { date: day.iso8601 }
    expect(batch.reload.bank_due_at).to eq(day.in_time_zone(zone))
    expect(flash[:notice]).to eq("Your bank pays whoever is left on #{day.strftime('%A, %B %-d')}.")

    patch manage_bank_day_payout_batch_path(batch), params: { date: (day + 30).iso8601 }
    expect(flash[:alert]).to eq("Choose a day from tomorrow to two weeks from now.")
    expect(batch.reload.bank_due_at).to eq(day.in_time_zone(zone))
  end

  it "keeps the default order and the deadline in Money settings" do
    get manage_money_settings_section_path(section: "payout_runs")
    expect(response.body).to include("Pay order", "Staff", "Performers", "Contractors", "Pay them from your balance as ticket money clears")

    patch manage_money_settings_payout_runs_path, params: { groups: %w[contractor performer], payout_waits_on_balance: "1", payout_bank_after_days: "5" }
    org.reload
    expect(org.payout_pay_order).to eq(%w[contractor performer staffing])
    expect(org.payout_bank_after_days).to eq(5)
    expect(org.payout_waits_on_balance).to be(true)

    patch manage_money_settings_payout_runs_path, params: { groups: %w[staffing], payout_waits_on_balance: "0", payout_bank_after_days: "lots" }
    org.reload
    expect(org.payout_bank_after_days).to eq(5)
    expect(org.payout_waits_on_balance).to be(false)
  end
end
