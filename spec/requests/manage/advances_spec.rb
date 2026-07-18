# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Advances", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let(:person) { create(:person, stripe_account_id: "acct_x", payouts_enabled: true) }

  before do
    org.people << person
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "issues an advance into the open performer run" do
    expect {
      post manage_create_money_production_advance_path(production), params: {
        person_advance: { person_id: person.id, original_amount: "50", advance_type: "general" }
      }
    }.to change(PersonAdvance, :count).by(1).and change(PayoutBatch, :count).by(1)

    advance = PersonAdvance.last
    expect(advance.in_payout_run?).to be(true)
    expect(response).to redirect_to(manage_payout_batch_path(PayoutBatch.last))
  end
end
