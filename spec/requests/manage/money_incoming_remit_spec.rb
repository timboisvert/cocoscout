# frozen_string_literal: true

require "rails_helper"

# Getting collected contract money to the org's own bank, from the payment
# page and the contract page — the whole flow lives in Money, not Courses.
RSpec.describe "Manage remitting collected contract money", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor_name: "SketchFest Chicago")
  end
  let!(:payment) do
    create(:contract_payment, :paid, contract: contract, direction: "incoming",
                                     amount: 250, due_date: 1.week.ago.to_date)
      .tap { |p| p.update!(stripe_checkout_session_id: "cs_#{p.id}", stripe_fee_cents: 800) }
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "the payment page" do
    it "offers Add to payout run once the org can receive payouts" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)

      get manage_money_incoming_payment_path(payment)

      body = response.body
      expect(body).to include("Getting this money to your bank")
      expect(body).to include("$242.00")
      expect(body).to include("Add to payout run")
      expect(body).to include(manage_remit_money_incoming_payment_path(payment))
    end

    it "points at connecting a bank when the org can't be paid yet" do
      get manage_money_incoming_payment_path(payment)

      expect(response.body).to include("Connect your bank")
      expect(response.body).not_to include("Add to payout run")
    end

    it "says the money is on a run, linking to it in Money, once remitted" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)
      ContractPaymentCollection.remit_to_organization!(payment)
      batch = payment.reload.payout_contribution.payout_batch

      get manage_money_incoming_payment_path(payment)

      expect(response.body).to include("on your payout run")
      expect(response.body).to include(manage_payout_batch_path(batch))
    end
  end

  describe "remitting" do
    it "queues the remittance on the org's run" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)

      post manage_remit_money_incoming_payment_path(payment)

      expect(response).to redirect_to(manage_money_incoming_payment_path(payment))
      contribution = payment.reload.payout_contribution
      expect(contribution).to be_present
      expect(contribution.payee).to eq(org)
      expect(contribution.amount_cents).to eq(24_200)
    end

    it "refuses while the org has no bank" do
      post manage_remit_money_incoming_payment_path(payment)

      expect(payment.reload.payout_contribution).to be_nil
      expect(flash[:alert]).to include("Connect your organization's bank")
    end
  end

  describe "the contract page" do
    it "offers Add to payout run on the paid row" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)

      get manage_contract_path(contract)

      expect(response.body).to include("Add to payout run")
      expect(response.body).to include(manage_remit_money_incoming_payment_path(payment))
    end

    it "links to the run in Money once the money is staged" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)
      ContractPaymentCollection.remit_to_organization!(payment)
      batch = payment.reload.payout_contribution.payout_batch

      get manage_contract_path(contract)

      expect(response.body).to include("In payout run")
      expect(response.body).to include(manage_payout_batch_path(batch))
    end
  end

  describe "the run page in Money" do
    it "offers Pay now (no ACH debit) when held money covers the whole run" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)
      ContractPaymentCollection.remit_to_organization!(payment)
      batch = payment.reload.payout_contribution.payout_batch

      get manage_payout_batch_path(batch)

      body = response.body
      expect(body).to include("Ready to send $242.00")
      expect(body).to include("Pay now")
      expect(body).to include(manage_fund_payout_batch_path(batch))
      expect(body).not_to include("Fund &amp; pay run")
      expect(body).not_to include("We debit your bank via ACH")
    end

    it "debits only the non-held remainder when show pay shares the run" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true,
                  funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account")
      ContractPaymentCollection.remit_to_organization!(payment)
      batch = payment.reload.payout_contribution.payout_batch
      performer = create(:person, stripe_account_id: "acct_perf", payouts_enabled: true)
      item = batch.items.create!(payee: performer, amount_cents: 5_000, status: "pending")
      batch.payout_contributions.create!(payout_batch_item: item, payee: performer,
                                         amount_cents: 5_000, label: "Show pay")
      batch.recalculate_total!

      get manage_payout_batch_path(batch)

      body = response.body
      expect(body).to include("We debit your bank via ACH")
      expect(body).to include("CocoScout already holds $242.00 of this run")
      expect(body).to include("debited only $50.00")
      expect(body).to include("Fund &amp; pay run")
    end

    it "pays the fully-held run with no bank debit when funded" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)
      ContractPaymentCollection.remit_to_organization!(payment)
      batch = payment.reload.payout_contribution.payout_batch
      allow(Stripe::Transfer).to receive(:create).and_return(double(id: "tr_remit"))

      post manage_fund_payout_batch_path(batch)

      expect(response).to redirect_to(manage_payout_batch_path(batch))
      expect(batch.reload.status).to eq("completed")
      expect(batch.funding_payment_intent_id).to be_nil # no ACH/card debit
      expect(Stripe::Transfer).to have_received(:create)
        .with(hash_including(amount: 24_200, destination: "acct_org"), anything)
    end

    it "refuses Pay now on a run that needs funding" do
      person = create(:person)
      batch = PayoutBatch.create!(organization: org, status: "draft", kind: "performer")
      batch.items.create!(payee: person, amount_cents: 1_000)

      post manage_pay_now_payout_batch_path(batch)

      expect(flash[:alert]).to include("needs funding")
      expect(batch.reload.status).to eq("draft")
    end
  end
end
