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
    create(:contract_payment, :outgoing, contract: contract, description: "Oct 11 — 50% to them", amount: 240, due_date: Date.current)
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
    expect(response.body).to include("Take out", manage_remove_line_payout_batch_path(batch, line))

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

  it "never reaches another organization's run" do
    other_owner = create(:user)
    other = create(:organization, :pro, owner: other_owner)
    other_batch = PayoutBatch.open_for(other, created_by: other_owner)

    delete manage_remove_line_payout_batch_path(other_batch, share.payout_contribution)
    expect(response).to have_http_status(:not_found)
    expect(share.reload).to be_in_payout_run
  end
end
