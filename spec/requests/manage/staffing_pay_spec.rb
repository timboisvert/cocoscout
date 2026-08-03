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

  it "lists only approved hours in the person's Hours modal" do
    pending = create(:staff_time_entry, organization: org, person: person)
    approved = create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner)

    get manage_staffing_pay_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("pay-hours-modal-#{member.id}")
    expect(response.body).to include(%(data-entry-id="#{approved.id}"))
    expect(response.body).not_to include(%(data-entry-id="#{pending.id}"))
  end

  describe "role-aware pricing (rates belong to the work, not the person)" do
    let(:bartender) { create(:house_role, organization: org, name: "Bartender") }
    let(:house_mgr) { create(:house_role, organization: org, name: "House Manager") }

    before do
      create(:staff_role_qualification, organization_staff_member: member, house_role: bartender, hourly_rate_cents: 1300)
      create(:staff_role_qualification, organization_staff_member: member, house_role: house_mgr, hourly_rate_cents: 2500)
    end

    it "pays included entries at their own role's rate plus ad-hoc hours at the chosen role's rate" do
      entry = create(:staff_time_entry, organization: org, person: person, house_role: bartender,
                     approved_at: Time.current, approved_by: owner,
                     started_at: Time.current.change(hour: 18), ended_at: Time.current.change(hour: 21)) # 3h

      post manage_create_staffing_pay_path, params: {
        payday: Date.current.to_s,
        lines: { member.id.to_s => { hours: "2", house_role_id: house_mgr.id.to_s, time_entry_ids: [ entry.id.to_s ] } }
      }

      batch = PayoutBatch.last
      # 3h × $13 (entry, as Bartender) + 2h × $25 (ad-hoc, as House Manager) = $89
      expect(batch.total_cents).to eq(3900 + 5000)
      expect(entry.reload.payout_batch_id).to eq(batch.id) # entry tied so it can't be paid twice
    end

    it "pays multiple ad-hoc lines, each at its own role's rate" do
      post manage_create_staffing_pay_path, params: {
        payday: Date.current.to_s,
        lines: { member.id.to_s => { adhoc: [ "3|#{bartender.id}", "2|#{house_mgr.id}" ] } }
      }

      # 3h × $13 (Bartender) + 2h × $25 (House Manager) = $89
      expect(PayoutBatch.last.total_cents).to eq(3900 + 5000)
    end

    it "ignores a forged role id from another organization" do
      foreign_role = create(:house_role, name: "Other Org Role", default_hourly_rate_cents: 99_900)

      post manage_create_staffing_pay_path, params: {
        payday: Date.current.to_s,
        lines: { member.id.to_s => { hours: "2", house_role_id: foreign_role.id.to_s } }
      }

      # Falls back to the member default rate ($20/hr), not the foreign role.
      expect(PayoutBatch.last.total_cents).to eq(4000)
    end
  end

  describe "draft autosave" do
    # PayDraft uses Rails.cache (null-store in tests) — give it a real store.
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "saves and restores the draft, and clears it after a paid run" do
      patch manage_staffing_pay_draft_path, params: { draft: '{"payday":"2026-08-01"}' }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(PayDraft.read(owner, org)).to eq('{"payday":"2026-08-01"}')

      post manage_create_staffing_pay_path, params: { lines: { member.id.to_s => { hours: "4" } } }

      expect(PayDraft.read(owner, org)).to be_nil
    end
  end

  it "renders the pay grid" do
    get manage_staffing_pay_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ready Rae").and include("Pay People")
  end

  it "wires the pay date to the live deposit estimate and blocks past dates in the picker" do
    get manage_staffing_pay_path
    expect(response.body).to include("deposit-estimate")            # live "when will they get it" estimate
    expect(response.body).to include(%(min="#{Date.current}"))      # picker floor: today
  end

  it "rejects a pay date in the past" do
    expect {
      post manage_create_staffing_pay_path, params: {
        payday: 2.days.ago.to_date.to_s,
        lines: { member.id.to_s => { hours: "4" } }
      }
    }.not_to change(PayoutBatch, :count)

    expect(response).to redirect_to(manage_staffing_pay_path)
    expect(flash[:alert]).to include("pick today or a later date")
  end

  it "adds the entered hours to the open staffing run (accumulate, not paid yet)" do
    expect {
      post manage_create_staffing_pay_path, params: {
        payday: Date.current.to_s,
        lines: { member.id.to_s => { hours: "4", bonus: "10" } }
      }
    }.to change(PayoutBatch, :count).by(1)

    batch = PayoutBatch.last
    expect(batch.kind).to eq("staff_pay")
    expect(batch.open?).to be(true) # still a draft — funded later from the runs page
    expect(batch.total_cents).to eq(9000) # 4 * $20 + $10 bonus
    expect(org.payout_balance_cents_for(person)).to eq(9000) # earned, awaiting payout
    expect(response).to redirect_to(manage_payout_batch_path(batch))
  end

  it "funds and pays the open staffing run through Connect from the runs page" do
    post manage_create_staffing_pay_path, params: { lines: { member.id.to_s => { hours: "4" } } }
    batch = PayoutBatch.last

    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded"))
    allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_1"))

    post manage_fund_payout_batch_path(batch)

    expect(batch.reload.status).to eq("completed")
    expect(org.payout_balance_cents_for(person)).to eq(0) # earned then paid
  end

  it "won't start a run when nobody has hours entered" do
    expect {
      post manage_create_staffing_pay_path, params: { lines: { member.id.to_s => { hours: "0" } } }
    }.not_to change(PayoutBatch, :count)
    expect(response).to redirect_to(manage_staffing_pay_path)
  end
end
