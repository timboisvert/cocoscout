# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::PayoutBatches", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, stripe_customer_id: "cus_1") }
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

  it "previews who is ready vs waiting on bank setup" do
    get manage_new_payout_batch_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ready Rita").and include("$40.00")     # connected → ready
    expect(response.body).to include("Nobank Ned").and include("$25.00")     # no bank → waiting
    expect(response.body).to include("Run payout")
  end

  it "runs a payout for connected payees and pays them" do
    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded"))
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

  it "is gated to the Pro plan" do
    free_owner = create(:user, password: password)
    free_org = create(:organization, owner: free_owner)
    create(:organization_role, :manager, user: free_owner, organization: free_org)
    post handle_signin_path, params: { email_address: free_owner.email_address, password: password }

    get manage_payout_batches_path
    expect(response).to have_http_status(:payment_required)
  end
end
