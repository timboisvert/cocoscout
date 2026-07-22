# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ContractWizard payments (v2 direction)", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:contract) { create(:contract, organization: org, status: :draft) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def save_payments(structure:, config:, who_sells: nil, payments: [ { "amount" => 100, "direction" => "incoming" } ])
    post manage_payments_contract_wizard_path(contract), params: {
      payments: payments.to_json,
      payment_structure: structure,
      payment_config: config.to_json,
      who_sells_tickets: who_sells
    }.compact
    contract.reload
  end

  it "Case 1 — revenue share, we sell → payments stamped outgoing" do
    save_payments(structure: "revenue_share", config: { "revenue_our_share" => 30 }, who_sells: "org")
    expect(contract.draft_payment_config["who_sells_tickets"]).to eq("org")
    expect(contract.draft_payment_config["settlement_basis"]).to eq("revenue_share")
    expect(contract.draft_payments.map { |p| p["direction"] }).to all(eq("outgoing"))
  end

  it "Case 2 — revenue share, they sell → payments stamped incoming" do
    save_payments(structure: "revenue_share", config: { "revenue_our_share" => 30 }, who_sells: "contractor")
    expect(contract.draft_payments.map { |p| p["direction"] }).to all(eq("incoming"))
  end

  it "Case 3 — flat fee minus ticket revenue → outgoing" do
    save_payments(structure: "flat_fee",
                  config: { "flat_fee_direction" => "ticket_revenue_minus_fee", "flat_fee_amount" => 500 },
                  payments: [ { "amount" => 0, "amount_tbd" => true, "direction" => "incoming" } ])
    expect(contract.draft_payment_config["settlement_basis"]).to eq("revenue_minus_fee")
    expect(contract.draft_payments.map { |p| p["direction"] }).to all(eq("outgoing"))
  end

  it "Case 4 — flat rental incoming → incoming" do
    save_payments(structure: "flat_fee",
                  config: { "flat_fee_direction" => "incoming", "flat_fee_amount" => 1000 },
                  payments: [ { "amount" => 1000, "direction" => "outgoing" } ])
    expect(contract.draft_payment_config["settlement_basis"]).to eq("flat")
    expect(contract.draft_payments.map { |p| p["direction"] }).to all(eq("incoming"))
  end
end
