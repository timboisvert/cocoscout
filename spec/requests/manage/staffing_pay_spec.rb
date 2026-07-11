# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing::Pay", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, stripe_customer_id: "cus_1") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:person) { create(:person, name: "Ready Rae", stripe_account_id: "acct_r", payouts_enabled: true) }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2000) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the pay grid" do
    get manage_staffing_pay_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ready Rae").and include("Pay People")
  end

  it "runs pay for the entered hours and pays through Connect" do
    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded"))
    allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_1"))

    expect {
      post manage_create_staffing_pay_path, params: {
        payday: Date.current.to_s, funding_method: "ach",
        lines: { member.id.to_s => { hours: "4", bonus: "10" } }
      }
    }.to change(PayoutBatch, :count).by(1)

    batch = PayoutBatch.last
    expect(batch.kind).to eq("staff_pay")
    expect(batch.total_cents).to eq(9000) # 4 * $20 + $10 bonus
    expect(batch.status).to eq("completed")
    expect(org.payout_balance_cents_for(person)).to eq(0) # earned then paid
    expect(response).to redirect_to(manage_payout_batch_path(batch))
  end

  it "won't start a run when nobody has hours entered" do
    expect {
      post manage_create_staffing_pay_path, params: { lines: { member.id.to_s => { hours: "0" } } }
    }.not_to change(PayoutBatch, :count)
    expect(response).to redirect_to(manage_staffing_pay_path)
  end
end
