# frozen_string_literal: true

require "rails_helper"

# Taking things back out of a draft payout run, from the run's page or a
# contract payment's row (Tim, 2026-10-11).
RSpec.describe "Taking a line out of a draft payout run", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:person) { create(:person, stripe_account_id: "acct_pav", payouts_enabled: true) }
  let(:contractor) { create(:contractor, organization: org, person: person, name: "Pavlov") }
  let(:contract) { create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: "Pavlov") }
  let!(:share) do
    create(:contract_payment, :outgoing, contract: contract, description: "Oct 11 — 50% to them", amount: 240, due_date: Date.new(2026, 10, 11))
  end

  before do
    ContractorPayoutRunService.add_contract_payment!(share)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "offers it on the contract row and the run page, and takes it out" do
    batch = PayoutBatch.current_open_draft(org)

    get manage_contract_path(contract)
    expect(response.body).to include("Take out of the payout run", remove_from_payout_run_manage_contract_contract_payment_path(contract, share))

    get manage_payout_batch_path(batch)
    line = share.payout_contribution
    # In the line's ⋮ menu, not a button on every line.
    expect(response.body).to include("Take out of this run", manage_remove_line_payout_batch_path(batch, line), 'aria-label="More actions for')
    expect(response.body).not_to include(">Take out<")

    delete manage_remove_line_payout_batch_path(batch, line)
    expect(response).to redirect_to(manage_payout_batch_path(batch))
    expect(flash[:notice]).to include("Took Oct 11 — 50% to them out of the run")
    expect(share.reload).not_to be_in_payout_run

    get manage_contract_path(contract)
    expect(response.body).to include("Add to payout run")
  end

  it "takes it out from the contract row too" do
    delete remove_from_payout_run_manage_contract_contract_payment_path(contract, share), headers: { "HTTP_REFERER" => manage_contract_url(contract) }
    expect(response).to redirect_to(manage_contract_url(contract))
    expect(flash[:notice]).to include("out of the payout run")
    expect(share.reload).not_to be_in_payout_run
  end

  # Ticket sales moved on after it went in: both menus offer the new amount.
  it "offers to update a share whose ticket sales moved on, and does it in one go" do
    contract.update!(draft_data: { "payment_structure" => "revenue_share",
                                   "payment_config" => { "revenue_our_share" => 50, "revenue_their_share" => 50, "revenue_settlement" => "per_event" } })
    show = create(:show, production: production, date_and_time: 1.day.ago)
    create(:show_financials, show: show, ticket_revenue: 495, data_confirmed: true)
    share.update_columns(show_id: show.id, notes: "Auto-calculated from show financials:")
    batch = PayoutBatch.current_open_draft(org)
    expect(ContractPaymentSyncService.current_amount(share.reload)).to eq(247.5)

    get manage_contract_path(contract)
    expect(response.body).to include("Update to $247.50", "Now $247.50 with sales since", refresh_in_payout_run_manage_contract_contract_payment_path(contract, share))
    get manage_payout_batch_path(batch)
    expect(response.body).to include("Update to $247.50", manage_refresh_line_payout_batch_path(batch, share.payout_contribution))

    post manage_refresh_line_payout_batch_path(batch, share.payout_contribution)
    expect(flash[:notice]).to include("$240.00 → $247.50")
    expect(share.reload.amount).to eq(247.5.to_d)
    expect(share.payout_contribution.amount_cents).to eq(24_750)
    expect(PayoutBatch.current_open_draft(org).total_cents).to eq(24_750)
  end

  it "never reaches another organization's run" do
    other_owner = create(:user)
    other = create(:organization, :pro, owner: other_owner)
    other_batch = PayoutBatch.open_for(other, created_by: other_owner)

    delete manage_remove_line_payout_batch_path(other_batch, share.payout_contribution)
    expect(response).to have_http_status(:not_found)
    expect(share.reload).to be_in_payout_run
  end
end
