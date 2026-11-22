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

  it "confirms what Pay now does, with no bank fee when the bank debit is days away" do
    get manage_payout_batch_path(batch)
    due = 3.days.from_now.in_time_zone(org.time_zone).strftime("%B %-d")
    expect(response.body).to include("Pay 1 of 2 payees today?",
                                     "Today, your CocoScout balance pays 1 payee ($50.00).",
                                     "Anyone still waiting on #{due} is paid from your bank that day.",
                                     "To pay them sooner, choose Pay the rest from my bank on this run.")
    expect(response.body).not_to include("free bank debit", "monthly bill", "Pay this run?")
  end

  it "keeps the bank fee in the confirm when the bank pays the rest right away" do
    allow(PayoutBatchService).to receive(:bank_due_at_for) { Time.current }
    get manage_payout_batch_path(batch)
    expect(response.body).to include("Pay 2 payees now?", "Your bank pays the other 1 ($30.00)", "monthly bill")
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

  # The list follows the saved pay order, numbered, in two groups: who the
  # balance covers now and who waits (Tim, 2026-11-22: "it should be in
  # priority order once I set it"; one line per payee, the state said once).
  it "lists the payees in pay order, grouped by who the balance covers right now" do
    covered = -> { response.body[response.body.index("data-balance-covers")...response.body.index("data-balance-left")] }
    waiting = -> { response.body[response.body.index("data-balance-waits")..] }
    get manage_payout_batch_path(batch)
    expect(covered.call).to include("Your CocoScout balance covers these now", "1 payee", "$50.00", "Sam Staff")
    expect(response.body).to include("$10.00 is left in your CocoScout balance after these, less than any payee below needs.")
    expect(waiting.call).to include("Waits for more balance or your bank", "Pat Performer")
    expect(response.body).not_to include("Ready to pay</span>")

    patch manage_pay_order_payout_batch_path(batch), params: { groups: %w[performer staffing contractor] }
    get manage_payout_batch_path(batch)
    expect(covered.call).to include("Pat Performer", "$30.00")
    expect(waiting.call).to include("Sam Staff")

    post manage_fund_payout_batch_path(batch)
    get manage_payout_batch_path(batch)
    expect(waiting.call).to include("Sam Staff")
    expect(response.body[response.body.index("Paid <span")..]).to include("Pat Performer")
  end

  # The balance skips a payee it can't cover and pays smaller ones after, so
  # the numbers say where each payee sits in the order.
  it "numbers payees by pay order when the balance skips one it can't cover" do
    quinn = create(:person, name: "Quinn Player", stripe_account_id: "acct_q", payouts_enabled: true)
    item = batch.items.create!(payee: quinn, amount_cents: 500, status: "pending")
    PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: quinn, amount_cents: 500, label: "Pay", category: "performer")
    batch.recalculate_total!
    patch manage_pay_order_payout_batch_path(batch),
          params: { groups: %w[staffing contractor performer], payees: [ "Person:#{performer.id}", "Person:#{quinn.id}" ] }

    get manage_payout_batch_path(batch)
    ranks = response.body.scan(/data-pay-rank>(\d+)</).flatten
    expect(ranks).to eq(%w[1 3 2])
    covers = response.body[response.body.index("data-balance-covers")...response.body.index("data-balance-left")]
    expect(covers).to include("Sam Staff", "Quinn Player", "2 payees", "$55.00")
    expect(response.body).to include("$5.00 is left in your CocoScout balance after these")
    expect(response.body[response.body.index("data-balance-waits")..]).to include("Pat Performer")
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
