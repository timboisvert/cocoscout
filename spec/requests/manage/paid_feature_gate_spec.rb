# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage paid-feature gate", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: organization) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  context "when the org is on the free plan" do
    let!(:organization) { create(:organization, owner: owner) }

    it "shows a feature-specific paywall for paid modules" do
      get manage_money_index_path
      expect(response).to have_http_status(:payment_required)
      expect(response.body).to include("Money &amp; Payments")

      get manage_staffing_index_path
      expect(response).to have_http_status(:payment_required)
      expect(response.body).to include("Staffing")

      get manage_reports_path
      expect(response).to have_http_status(:payment_required)
      expect(response.body).to include("Reports")

      get manage_signups_all_auditions_path
      expect(response).to have_http_status(:payment_required)
      expect(response.body).to include("Auditions")
    end

    it "gates Contracts as its own feature rather than as part of Money" do
      get manage_contracts_path
      expect(response).to have_http_status(:payment_required)
      expect(response.body).to include("Contracts")
      expect(response.body).not_to include("Money &amp; Payments")

      get manage_contract_settings_path
      expect(response).to have_http_status(:payment_required)

      get manage_billing_upgrade_path(feature: "contracts")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Book the run")
    end

    it "serves rich upgrade content at the modal endpoint" do
      get manage_billing_upgrade_path(feature: "money")
      expect(response).to have_http_status(:ok)
      # The feature name leads (no icon), plus rich capability copy.
      expect(response.body).to include("Money &amp; Payments")
      expect(response.body).to include("Performer payouts")
      expect(response.body).to include("Pro also includes")
    end

    it "404s the modal endpoint for an unknown feature" do
      get manage_billing_upgrade_path(feature: "nope")
      expect(response).to have_http_status(:not_found)
    end

    it "still allows free modules (including Documents)" do
      get manage_messages_path
      expect(response).to have_http_status(:ok)

      get manage_contacts_path
      expect(response).to have_http_status(:ok)

      get manage_org_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects the legacy billing page to the org's Billing & Plan tab" do
      get manage_billing_path
      expect(response).to redirect_to(manage_organization_path(organization, anchor: "tab-4"))
    end
  end

  context "when the org is comped Pro" do
    let!(:organization) { create(:organization, :pro, owner: owner) }

    it "allows paid modules" do
      get manage_money_index_path
      expect(response).to have_http_status(:ok)

      get manage_staffing_index_path
      expect(response).to have_http_status(:ok)

      get manage_reports_path
      expect(response).to have_http_status(:ok)
    end
  end
end
