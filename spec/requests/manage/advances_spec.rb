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

  describe "the slim list view" do
    let!(:to_pay) do
      create(:person_advance, production: production, person: create(:person, name: "Pat Payee"),
                              original_amount: 100, remaining_balance: 100, status: "pending")
    end
    let!(:to_repay) do
      create(:person_advance, :paid, :partial, production: production, person: create(:person, name: "Ronn Repay"),
                                                original_amount: 100, remaining_balance: 50)
    end

    it "shows two amount boxes and a slim grid with an advances accordion" do
      get manage_money_advances_path
      expect(response.body).to include("Advances to be paid").and include("Advances to be repaid")
      expect(response.body).to include("$100.00").and include("$50.00")
      expect(response.body).not_to include("Issued This Month")
      expect(response.body).to include("advance-events-#{production.id}")
    end

    it "renders the lazy advances frame split into to-pay and to-repay" do
      get manage_money_production_advance_events_path(production)
      expect(response.body).to include("Pat Payee").and include("Ronn Repay")
      expect(response.body).to include("To pay").and include("To repay")
      expect(response.body).to include(manage_money_advance_path(production, to_pay))
    end
  end
end
