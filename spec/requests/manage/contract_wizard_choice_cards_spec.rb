# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Financials step choice cards", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:contract) { create(:contract, organization: org, contractor_name: "Rental Co", status: "draft") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the settings as radio cards rather than dropdowns" do
    get manage_payments_contract_wizard_path(contract)

    expect(response).to have_http_status(:ok)
    %w[flat_fee_direction_choice per_event_direction_choice
       per_event_timing_choice per_event_terms_choice
       revenue_source_choice revenue_settlement_choice].each do |group|
      expect(response.body).to include(%(name="#{group}")), "expected #{group} cards"
    end
    # Each still mirrors into the hidden input the controller reads.
    expect(response.body).to include(%(type="hidden" data-contract-payments-target="flatFeeDirection"))
    expect(response.body).to include(%(type="hidden" data-contract-payments-target="perEventTerms"))
  end

  it "checks the card matching what's already saved" do
    contract.update_draft_step(:payment_config, { "flat_fee_direction" => "outgoing" })

    get manage_payments_contract_wizard_path(contract)

    expect(response.body).to match(/name="flat_fee_direction_choice" value="outgoing"[^>]*checked/m)
  end

  it "defaults a revenue share to an even split" do
    get manage_payments_contract_wizard_path(contract)

    expect(response.body).to match(/data-contract-payments-target="revenueOurShare"[^>]*value="50"/)
    expect(response.body).to match(/data-contract-payments-target="revenueTheirShare"[^>]*value="50"/)
  end

  it "keeps a saved split rather than resetting it to even" do
    contract.update_draft_step(:payment_config,
                               { "revenue_our_share" => "30", "revenue_their_share" => "70" })

    get manage_payments_contract_wizard_path(contract)

    expect(response.body).to match(/data-contract-payments-target="revenueOurShare"[^>]*value="30"/)
  end

  it "carries no running payment summary — the review step covers that" do
    get manage_payments_contract_wizard_path(contract)

    expect(response.body).not_to include("Payment Summary")
  end

  describe "the yes/no options" do
    it "offers the volume discount as cards once there's more than one date" do
      contract.update_draft_step(:bookings, [
        { "starts_at" => 1.week.from_now.iso8601 },
        { "starts_at" => 2.weeks.from_now.iso8601 }
      ])

      get manage_payments_contract_wizard_path(contract)

      expect(response.body).to include(%(name="per_event_discount_choice"))
      expect(response.body).to include("Discount for booking several")
    end

    it "doesn't mention a volume discount for a single date" do
      contract.update_draft_step(:bookings, [ { "starts_at" => 1.week.from_now.iso8601 } ])

      get manage_payments_contract_wizard_path(contract)

      expect(response.body).not_to include(%(name="per_event_discount_choice"))
      expect(response.body).not_to include("Volume discount")
    end

    it "offers the minimum guarantee as cards" do
      get manage_payments_contract_wizard_path(contract)

      expect(response.body).to include(%(name="revenue_guarantee_choice"))
      expect(response.body).to include("Guarantee a minimum")
      # No stray checkbox left behind — it's a hidden input plus cards now.
      expect(response.body).not_to include(%(type="checkbox" data-contract-payments-target="revenueGuarantee"))
    end
  end

  describe "the payments list" do
    it "shows the payments the deal creates, with an Add another payment button" do
      get manage_payments_contract_wizard_path(contract)

      expect(response.body).to include("Payments on this contract")
      expect(response.body).to include("Add another payment")
      expect(response.body).to include(%(data-contract-payments-target="list"))
    end

    it "adds payments through a modal, with direction as cards" do
      get manage_payments_contract_wizard_path(contract)

      expect(response.body).to include(%(data-contract-payments-target="paymentModal"))
      expect(response.body).to include(%(name="extra_payment_direction_choice"))
      expect(response.body).to include("Add a payment")
    end
  end
end
