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
    end

    it "leaves auditions & sign-ups open on the free plan" do
      get manage_signups_all_auditions_path
      expect(response).not_to have_http_status(:payment_required)
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

    # The gate maps controllers, so every controller that touches a Pro
    # module's data has to be in the map — including the small nested ones
    # (a contract's rentals and appendixes, Money's expenses and receipts).
    it "gates the nested Contracts and Money controllers too" do
      production = create(:production, organization: organization, production_type: "third_party")
      contract = create(:contract, :active, organization: organization, production: production)

      post manage_contract_space_rentals_path(contract), params: { space_rental: { starts_at: 1.week.from_now } }
      expect(response).to have_http_status(:payment_required)
      expect(contract.space_rentals.count).to eq(0)

      post manage_contract_contract_appendixes_path(contract), params: { contract_appendix: { heading: "Extra", body: "x" } }
      expect(response).to have_http_status(:payment_required)

      get manage_money_financials_production_expenses_path(production)
      expect(response).to have_http_status(:payment_required)

      post manage_upload_receipt_expense_item_path(1), as: :json
      expect(response).to have_http_status(:payment_required)
    end

    # Performer agreements ride on the productions controller (a free module),
    # so those actions check the plan themselves — like update_pay does.
    it "keeps performer agreements (roster, reminders, the settings) behind Pro" do
      production = create(:production, organization: organization)
      template = organization.agreement_templates.create!(name: "Code of conduct", content: "<p>Be kind</p>")

      get agreement_status_manage_production_path(production)
      expect(response).to redirect_to(edit_manage_production_path(production, anchor: "tab-4"))

      post send_agreement_reminders_manage_production_path(production)
      expect(response).to redirect_to(edit_manage_production_path(production, anchor: "tab-4"))

      patch manage_production_path(production), params: {
        production: { name: production.name, agreement_template_id: template.id, agreement_required: "1", agreement_auto_send: "1" }
      }
      production.reload
      expect(production.agreement_template_id).to be_nil
      expect(production.agreement_required).to be_falsey
      expect(production.agreement_auto_send).to be_falsey
    end

    it "marks Pro surfaces on free pages as Pro and locked, the same way everywhere" do
      production = create(:production, organization: organization)
      get edit_manage_production_path(production)
      body = response.body
      # The Agreement tab and the Pay tab wear the same pill + padlock…
      expect(body.scan('aria-label="Pro feature"').size).to be >= 3
      # …and the Agreement panel is the same locked card as Pay: header pill + Upgrade button, no bespoke upsell box.
      expect(body).to include("Performer agreements")
      expect(body).to include("Pro feature")
      expect(body).not_to include("Performer Agreements is a Pro feature")
      expect(body).to include(manage_billing_upgrade_path(feature: "agreements"))
      expect(body).to include(manage_billing_upgrade_path(feature: "money"))

      # Org settings: the Agreements tab says Pro and is locked; the section is the same locked card.
      get section_manage_organization_path(organization, section: "agreements")
      expect(response.body).to include("Agreement Templates")
      expect(response.body).to include(manage_billing_upgrade_path(feature: "agreements"))
      expect(response.body).to match(/Agreements\s*<span[^>]*>Pro<\/span>/m)
    end

    it "marks the course page's Financials link (Money) as Pro and locked" do
      production = create(:production, organization: organization, production_type: "course")
      offering = create(:course_offering, production: production)
      get manage_course_offering_path(offering)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Financials")
      expect(response.body).to include('data-upgrade-feature="money"')
    end

    it "still allows free modules (including Documents)" do
      get manage_messages_path
      expect(response).to have_http_status(:ok)

      get manage_contacts_path
      expect(response).to have_http_status(:ok)

      get manage_org_documents_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects the legacy billing page to the org's Billing & Plan section" do
      get manage_billing_path
      expect(response).to redirect_to(section_manage_organization_path(organization, section: "billing"))
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

    it "still says Pro on Pro surfaces, without a padlock" do
      production = create(:production, organization: organization)
      get edit_manage_production_path(production)
      body = response.body
      expect(body).to include(">Pro</span>")
      expect(body).not_to include('aria-label="Pro feature"><path') # no lock in the tab strip
      expect(body).to include("Agreement Settings")

      get section_manage_organization_path(organization, section: "agreements")
      expect(response.body).to match(/Agreements\s*<span[^>]*>Pro<\/span>/m)
      expect(response.body).to include("New Template")
    end
  end
end
