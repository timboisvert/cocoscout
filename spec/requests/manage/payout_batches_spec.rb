# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::PayoutBatches", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let!(:ready) do
    p = create(:person, name: "Ready Rita", stripe_account_id: "acct_r", payouts_enabled: true)
    PayoutLedgerEntry.post!(organization: org, payee: p, entry_type: "earning", amount_cents: 4000)
    p
  end
  let!(:not_ready) do
    p = create(:person, name: "Nobank Ned")
    PayoutLedgerEntry.post!(organization: org, payee: p, entry_type: "earning", amount_cents: 2500)
    p
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "lists payout runs" do
    get manage_payout_batches_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Payout Runs")
  end

  describe "funding source" do
    it "shows the connected source on the index" do
      org.update!(funding_payment_method_label: "Chase •••• 6789")
      get manage_payout_batches_path
      expect(response.body).to include("Chase •••• 6789")
    end

    it "saves the funding source when returning from Stripe" do
      allow_any_instance_of(PayoutFundingService).to receive(:save_from_session!)
      get manage_payout_funding_return_path(session_id: "cs_1")
      expect(response).to redirect_to(manage_payout_batches_path)
    end

    it "removes the funding source" do
      delete manage_remove_payout_funding_path
      expect(org.reload.funding_payment_method_id).to be_nil
      expect(response).to redirect_to(manage_payout_batches_path)
    end
  end

  it "saves a weekly payout schedule" do
    patch manage_payout_batch_schedule_path, params: {
      payout_schedule: "weekly", weekly_day: "5", payout_funding_method: "card"
    }
    org.reload
    expect(org.payout_schedule).to eq("weekly")
    expect(org.payout_schedule_day).to eq(5)
    expect(org.payout_funding_method).to eq("card")
    expect(response).to redirect_to(manage_payout_batches_path)
  end

  it "previews who is ready vs waiting on bank setup" do
    get manage_new_payout_batch_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ready Rita").and include("$40.00")     # connected → ready
    expect(response.body).to include("Nobank Ned").and include("$25.00")     # no bank → waiting
    expect(response.body).to include("Run payout")
  end

  it "runs a payout for connected payees and pays them" do
    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded", amount: 5000))
    allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_1"))

    expect { post manage_create_payout_batch_path, params: { funding_method: "ach" } }
      .to change { PayoutBatch.count }.by(1)

    batch = PayoutBatch.last
    expect(batch.items.map(&:payee)).to eq([ ready ])          # only the connected payee
    expect(batch.status).to eq("completed")
    expect(org.payout_balance_cents_for(ready)).to eq(0)       # paid, balance cleared
    expect(org.payout_balance_cents_for(not_ready)).to eq(2500) # untouched
    expect(response).to redirect_to(manage_payout_batch_path(batch))
  end

  describe "a run with someone still waiting on a bank" do
    before do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded", amount: 5000))
      allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_1"))
    end

    let!(:batch) do
      b = PayoutBatch.create!(organization: org, kind: "staff_pay", status: "draft", trigger: "manual")
      b.items.create!(payee: ready, amount_cents: 4000, status: "pending")
      b.items.create!(payee: not_ready, amount_cents: 2500, status: "pending")
      b.recalculate_total!
      b
    end

    it "funds the full total, pays the ready, and keeps the run open as partially paid" do
      post manage_fund_payout_batch_path(batch)

      batch.reload
      expect(batch.status).to eq("partially_paid")
      expect(batch.completed_at).to be_nil
      expect(batch.items.find_by(payee: ready).status).to eq("paid")
      # Skipped, not failed — the money waits on this run.
      expect(batch.items.find_by(payee: not_ready).status).to eq("pending")

      get manage_payout_batch_path(batch)
      expect(response.body).to include("still to pay on this run")
      expect(response.body).to include("Nobank Ned")
      # No one new is ready, so no Pay remaining button yet.
      expect(response.body).not_to include("confirm-pay-remaining")
    end

    it "pays the remaining person once they connect a bank, then completes" do
      post manage_fund_payout_batch_path(batch)
      not_ready.update!(stripe_account_id: "acct_n", payouts_enabled: true)

      get manage_payout_batch_path(batch)
      expect(response.body).to include("Pay remaining")

      post manage_pay_remaining_payout_batch_path(batch)

      batch.reload
      expect(batch.status).to eq("completed")
      expect(batch.completed_at).to be_present
      expect(batch.items.where.not(status: "paid")).to be_empty
      expect(org.payout_balance_cents_for(not_ready)).to eq(0)
    end

    it "shows the run's money by payee state, and filters the payments list by it" do
      get manage_payout_batch_path(batch)
      # State boxes: $40 ready (Rita has a bank), $25 waiting (Ned doesn't).
      expect(response.body).to include("Ready to pay").and include("Waiting on bank info")
      expect(response.body).to include("$40.00").and include("$25.00")
      expect(response.body).to include("1 payee hasn&#39;t connected")
      # The box / filter link for the waiting slice.
      expect(response.body).to include(manage_payout_batch_path(batch, state: :waiting))

      get manage_payout_batch_path(batch, state: :waiting)
      expect(response.body).to include("Nobank Ned")
      # Rita's payment row is filtered out (her name still appears nowhere else on a draft run).
      expect(response.body).not_to include("Ready Rita")
    end

    it "lists what each run is waiting on in the runs index" do
      post manage_fund_payout_batch_path(batch)
      get manage_payout_batches_path
      expect(response.body).to include("Waiting on bank")
      expect(response.body).to include("1 payee waiting on bank info")
      expect(response.body).to include("$25.00")
      # The top box says how much is stuck on missing bank info, and on how many people.
      expect(response.body).to include("1 payee across 1 run")
    end

    it "refuses pay_remaining on an unfunded run" do
      post manage_pay_remaining_payout_batch_path(batch)
      expect(response).to redirect_to(manage_payout_batch_path(batch))
      follow_redirect!
      expect(response.body).to include("hasn&#39;t been funded")
    end
  end

  describe "submitted notification email" do
    include ActiveJob::TestHelper

    before do
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded", amount: 5000))
      allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_1"))
      ContentTemplate.create!(
        key: "payout_run_submitted", name: "Payout Run Submitted",
        subject: "Payout run submitted — {{total}} to {{people_count}}",
        body: "<p>{{payee_lines}}</p><p>Expected {{expected_window}}</p><p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
        category: "notifications", channel: "email", active: true
      )
      org.update!(payout_notification_user_ids: [ owner.id ])
    end

    after { clear_enqueued_jobs }

    let!(:batch) do
      b = PayoutBatch.create!(organization: org, kind: "staff_pay", status: "draft", trigger: "manual")
      b.items.create!(payee: ready, amount_cents: 4000, status: "pending")
      b.recalculate_total!
      b
    end

    it "emails the chosen managers with names, amounts, the window, and a link" do
      expect { post manage_fund_payout_batch_path(batch) }
        .to have_enqueued_job(PayoutRunSubmittedNotificationJob).with(batch.id)

      expect { perform_enqueued_jobs(only: PayoutRunSubmittedNotificationJob) }
        .to change { ActionMailer::Base.deliveries.count }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ owner.email_address ])
      expect(mail.subject).to include("$40.00").and include("1 payee")
      raw = mail.to_s
      expect(raw).to include("Ready Rita")
      expect(raw).to include("$40.00")
      expect(raw).to include("payout-runs/#{batch.id}")
    end

    it "sends nothing when no recipients are chosen" do
      org.update!(payout_notification_user_ids: [])
      post manage_fund_payout_batch_path(batch)
      expect { perform_enqueued_jobs(only: PayoutRunSubmittedNotificationJob) }
        .not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  it "links a payment component back to the show payout that created it" do
    show = create(:show, production: create(:production, organization: org), event_type: :show, date_and_time: 3.days.ago)
    payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 40)
    ShowPayoutLineItem.create!(show_payout: payout, payee: ready, amount: 40)
    PerformerPayoutRunService.add_show_payout!(payout)

    batch = PayoutBatch.where(kind: "performer").order(:id).last
    get manage_payout_batch_path(batch)

    expect(response).to have_http_status(:ok)
    # The contribution row traces back to the show's payout page.
    expect(response.body).to include(manage_money_show_payout_path(show))
  end

  it "is gated to the Pro plan" do
    free_owner = create(:user, password: password)
    free_org = create(:organization, owner: free_owner)
    create(:organization_role, :manager, user: free_owner, organization: free_org)
    post handle_signin_path, params: { email_address: free_owner.email_address, password: password }

    get manage_payout_batches_path
    expect(response).to have_http_status(:payment_required)
  end
end
