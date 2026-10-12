# frozen_string_literal: true

require "rails_helper"

# "Close this run" on a run that's paid except for people with no bank
# (Tim, 2026-10-12), and the trail it leaves on both runs.
RSpec.describe "Closing out a payout run", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:banked) { create(:person, name: "Banked Bea", stripe_account_id: "acct_bea", payouts_enabled: true) }
  let(:unbanked) { create(:person, name: "Pat Performer") }
  let!(:run) do
    show = create(:show, production: production, event_type: :show, date_and_time: 3.days.ago)
    payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 100)
    ShowPayoutLineItem.create!(show_payout: payout, payee: banked, amount: 60)
    ShowPayoutLineItem.create!(show_payout: payout, payee: unbanked, amount: 40)
    PerformerPayoutRunService.add_show_payout!(payout)
    batch = PayoutBatch.current_open_draft(org)
    batch.update!(status: "partially_paid", funding_status: "succeeded")
    batch.items.find_by(payee: banked).mark_paid!(transfer_id: "tr_bea")
    batch.reload
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers it, closes the run out, and shows the move on both runs" do
    get manage_payout_batch_path(run)
    expect(response.body).to include("Close this run", "Everyone else is paid", "Pat Performer", manage_close_out_payout_batch_path(run))

    post manage_close_out_payout_batch_path(run)
    expect(response).to redirect_to(manage_payout_batch_path(run))
    expect(flash[:notice]).to include("Pat Performer moved to the Waiting on bank info run")

    get manage_payout_batch_path(run)
    expect(response.body).to include("Closed out", "moved to the Waiting on bank info run on", "Pat Performer", "Open the Waiting on bank info run")
    expect(response.body).not_to include("Close this run")

    waiting = org.payout_batches.find_by!(waiting_on_banks: true)
    get manage_payout_batch_path(waiting)
    expect(response.body).to include("Everyone here is waiting to connect a bank", "Pat Performer", manage_payout_batch_path(run))
  end

  it "never closes out another organization's run" do
    other_owner = create(:user)
    other = create(:organization, :pro, owner: other_owner)
    other_run = other.payout_batches.create!(kind: "payout", status: "partially_paid", funding_status: "succeeded")

    post manage_close_out_payout_batch_path(other_run)
    expect(response).to have_http_status(:not_found)
    expect(other_run.reload.status).to eq("partially_paid")
  end
end
