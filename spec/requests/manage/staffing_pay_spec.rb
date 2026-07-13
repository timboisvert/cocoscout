# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing::Pay", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:person) { create(:person, name: "Ready Rae", stripe_account_id: "acct_r", payouts_enabled: true) }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2000) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "only offers approved hours to pull into a run" do
    pending = create(:staff_time_entry, organization: org, person: person)
    approved = create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner)

    get manage_staffing_pay_time_entries_path(person_id: person.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-entry-id="#{approved.id}"))
    expect(response.body).not_to include(%(data-entry-id="#{pending.id}"))
  end

  describe "draft autosave" do
    # PayDraft uses Rails.cache (null-store in tests) — give it a real store.
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "saves and restores the draft, and clears it after a paid run" do
      patch manage_staffing_pay_draft_path, params: { draft: '{"payday":"2026-08-01"}' }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(PayDraft.read(owner, org)).to eq('{"payday":"2026-08-01"}')

      allow(Stripe::PaymentIntent).to receive(:create).and_return(double(id: "pi_1", status: "succeeded"))
      allow(Stripe::Transfer).to receive(:create).and_return(double(id: "tr_1"))
      post manage_create_staffing_pay_path, params: { funding_method: "ach", lines: { member.id.to_s => { hours: "4" } } }

      expect(PayDraft.read(owner, org)).to be_nil
    end
  end

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
