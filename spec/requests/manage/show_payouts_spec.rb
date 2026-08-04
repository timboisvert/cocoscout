# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ShowPayouts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
  let!(:financials) { create(:show_financials, :complete, show: show, ticket_revenue: 500) }
  let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 180) }
  let!(:li_paid) do
    ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Paid Pat"), amount: 60)
      .tap { |li| li.update_columns(manually_paid: true) }
  end
  let!(:li_unpaid) do
    ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Owed Ollie", stripe_account_id: "acct_1", payouts_enabled: true), amount: 120)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "shows the payout amounts as at-a-glance boxes" do
    get manage_money_show_payout_path(show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Total payout")
    expect(response.body).to include("$180.00")     # full net payout
    expect(response.body).to include("Already paid")
    expect(response.body).to include("$60.00")      # what's already been paid
  end

  it "offers an add-to-run preview modal instead of a confirm alert" do
    get manage_money_show_payout_path(show)
    expect(response.body).to include("add-to-run-modal")
    expect(response.body).to include("Owed Ollie")            # eligible unpaid performer listed
    expect(response.body).not_to include("turbo_confirm=\"Add these performer payouts")
  end

  it "stays on the payout page after adding to the run (doesn't jump to the batch)" do
    post manage_add_to_run_money_show_payout_path(show)
    expect(response).to redirect_to(manage_money_show_payout_path(show))
  end

  it "adds no-bank payees to the run too — their money rides it until they connect" do
    nobank = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Nobank Nel"), amount: 30)

    post manage_add_to_run_money_show_payout_path(show)

    expect(nobank.reload.in_payout_run?).to be(true)
    expect(li_unpaid.reload.in_payout_run?).to be(true)

    get manage_money_show_payout_path(show)
    expect(response.body).to include("awaiting their bank")
  end

  it "still offers Add to payout run for a line that missed the first add (e.g. a producer allocation)" do
    producer = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Gib Producer"),
                                          amount: 29.30, is_individual_allocation: true)
    # First add stages only Ollie (picker selection) — the show is now "in a run".
    post manage_add_to_run_money_show_payout_path(show), params: { line_item_ids: [ li_unpaid.id ] }
    expect(producer.reload.in_payout_run?).to be(false)

    # The page must still offer to stage the leftover line…
    get manage_money_show_payout_path(show)
    expect(response.body).to include("Add to payout run")
    expect(response.body).to include("Gib Producer")

    # …and adding again picks him up.
    post manage_add_to_run_money_show_payout_path(show)
    expect(producer.reload.in_payout_run?).to be(true)
  end

  it "only adds the picker's checked lines; unchecked people stay off the run" do
    nobank = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Nobank Nel"), amount: 30)

    post manage_add_to_run_money_show_payout_path(show), params: { line_item_ids: [ li_unpaid.id ] }

    expect(li_unpaid.reload.in_payout_run?).to be(true)
    expect(nobank.reload.in_payout_run?).to be(false)
  end

  describe "marking an in-run line paid another way" do
    before { org.update!(enabled_offline_payout_methods: [ "cash" ]) }

    it "on a DRAFT run: records the payment and removes them — no credit minted" do
      nobank = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Nobank Nel"), amount: 30)
      post manage_add_to_run_money_show_payout_path(show)
      expect(nobank.reload.in_payout_run?).to be(true)

      post manage_mark_line_item_paid_money_show_payout_path(show, nobank), params: { payment_method: "cash" }

      nobank.reload
      expect(nobank.manually_paid).to be(true)
      expect(nobank.in_payout_run?).to be(false)
      expect(PayoutFundingCredit.count).to eq(0)
    end

    it "on a FUNDED run: records the payment, releases them, and mints funding credit" do
      org.update!(stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account")
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded"))
      allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_1"))

      nobank = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Nobank Nel"), amount: 30)
      post manage_add_to_run_money_show_payout_path(show)
      batch = PayoutBatch.where(kind: "performer").order(:id).last
      PayoutBatchService.fund!(batch, method: "ach")
      expect(batch.reload.status).to eq("partially_paid") # Nobank Nel is waiting

      post manage_mark_line_item_paid_money_show_payout_path(show, nobank), params: { payment_method: "cash" }

      nobank.reload
      expect(nobank.manually_paid).to be(true)
      expect(nobank.in_payout_run?).to be(false)
      credit = PayoutFundingCredit.last
      expect(credit.organization).to eq(org)
      expect(credit.amount_cents).to eq(3000)
      # The run has nothing left waiting — it completes.
      expect(batch.reload.status).to eq("completed")

      # The credit shrinks the next run's debit.
      next_batch = PayoutBatch.create!(organization: org, kind: "staff_pay", status: "draft", trigger: "manual")
      next_batch.items.create!(payee: create(:person, name: "Next Ned", stripe_account_id: "acct_n", payouts_enabled: true), amount_cents: 5000, status: "pending")
      next_batch.recalculate_total!
      expect(Stripe::PaymentIntent).to receive(:create).with(hash_including(amount: 2000)).and_return(double("pi", id: "pi_2", status: "succeeded"))
      PayoutBatchService.fund!(next_batch, method: "ach")
      expect(PayoutFundingCredit.available_cents(org)).to eq(0)
    end
  end

  describe "removing a payee from the run" do
    before { post manage_add_to_run_money_show_payout_path(show) } # queues Owed Ollie

    it "offers a Remove from run control while queued" do
      expect(li_unpaid.reload.in_payout_run?).to be(true)
      get manage_money_show_payout_path(show)
      expect(response.body).to include("Remove from run")
    end

    it "pulls the payee out of the open run but keeps them owed" do
      expect(li_unpaid.reload.in_payout_run?).to be(true)

      delete manage_remove_line_item_from_run_money_show_payout_path(show, li_unpaid)

      expect(response).to redirect_to(manage_money_show_payout_path(show))
      expect(li_unpaid.reload.in_payout_run?).to be(false)
      # Still owed — the earning stays on the ledger, only the pending transfer is gone.
      expect(li_unpaid.reload.paid?).to be(false)
    end

    it "never disturbs an already-paid item" do
      # Owed Ollie's transfer completed; removal should be a no-op, not a data wipe.
      contribution = li_unpaid.reload.payout_contribution
      contribution.payout_batch_item.update_columns(status: "paid")

      delete manage_remove_line_item_from_run_money_show_payout_path(show, li_unpaid)

      expect(PayoutContribution.exists?(contribution.id)).to be(true)
    end
  end

  describe "mark paid another way (offline)" do
    # Not bank-connected and unpaid — the only state that offers the offline action.
    let!(:li_offline) do
      ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Cash Casey"), amount: 40)
    end

    it "hides the action when the org has declared no offline methods" do
      get manage_money_show_payout_path(show)
      expect(response.body).not_to include("payment-actions#showMarkPaidModal")
    end

    context "with offline methods enabled in Money settings" do
      before { org.update!(enabled_offline_payout_methods: %w[cash zelle]) }

      it "offers the action for a not-bank-connected unpaid payee" do
        get manage_money_show_payout_path(show)
        expect(response.body).to include("payment-actions#showMarkPaidModal")
        expect(response.body).to include('data-item-name="Cash Casey"')
      end

      it "records the offline payment and shows the payee as paid" do
        post manage_mark_line_item_paid_money_show_payout_path(show, li_offline),
          params: { payment_method: "zelle", payment_notes: "Zelle #55" }

        expect(response).to redirect_to(manage_money_show_payout_path(show))
        expect(li_offline.reload).to be_paid
        expect(li_offline.payment_method).to eq("zelle")
        expect(li_offline.payment_notes).to eq("Zelle #55")
        expect(li_offline.payout_reference_id).to be_nil # not a Stripe movement
      end

      it "stamps paid_at from a supplied paid_date" do
        post manage_mark_line_item_paid_money_show_payout_path(show, li_offline),
          params: { payment_method: "cash", paid_date: "2026-05-01" }

        expect(li_offline.reload).to be_paid
        expect(li_offline.paid_at.to_date).to eq(Date.new(2026, 5, 1))
      end
    end
  end

  describe "a line item calculated to nothing owed ($0)" do
    # A custom scheme (or a fully-offset advance) can leave a payee owed nothing.
    let!(:li_zero) do
      ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Zero Zoe"), amount: 0)
    end

    it "offers a one-click Mark done instead of the pay-another-way flow" do
      get manage_money_show_payout_path(show)
      expect(response.body).to include("Mark done").and include("nothing owed")
    end

    it "marks the $0 line paid with no method on one click" do
      post manage_mark_line_item_paid_money_show_payout_path(show, li_zero.id.to_s)

      expect(response).to redirect_to(manage_money_show_payout_path(show))
      expect(li_zero.reload).to be_paid
      expect(li_zero.payment_method).to be_nil
    end
  end
end
