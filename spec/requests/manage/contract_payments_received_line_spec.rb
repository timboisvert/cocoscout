# frozen_string_literal: true

require "rails_helper"

# The contract page's "Payments received" counted charges that were deducted
# from a payout: settled, but nobody paid them (Tim, 2026-11-08). Received is
# money that arrived; what came out of their payouts has a line of its own.
RSpec.describe "Manage::Contracts payments received line", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }

  def line(html, label)
    html.gsub(/\s+/, " ")[%r{#{Regexp.escape(label)}</dt> <dd[^>]*>([^<]*)</dd>}, 1]&.strip
  end

  before do
    create(:contract_payment, :paid, contract: contract, direction: "incoming", amount: 250,
                                     description: "Rent", due_date: 1.week.ago.to_date)
      .update!(payment_method: "check")
    create(:contract_payment, contract: contract, direction: "outgoing", amount: 510,
                              description: "Their share", due_date: 2.days.ago.to_date)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "counts only money that arrived, and says what was deducted from their payouts" do
    2.times do |i|
      create(:contract_payment, :paid, contract: contract, direction: "incoming", amount: 50,
                                       description: "Booth Tech #{i}", due_date: 3.days.ago.to_date,
                                       settlement_method: "payout_deduction")
        .update!(payment_method: "payout_deduction")
    end

    get manage_contract_path(contract)

    expect(line(response.body, "Payments received")).to eq("$250.00")
    expect(line(response.body, "Deducted from their payouts")).to eq("$100.00")
    expect(line(response.body, "Payments scheduled out, before deductions")).to eq("$510.00")
    # Financials still counts a deducted charge as income.
    expect(contract.total_incoming).to eq(350)
  end

  it "has no deductions line when nothing was deducted" do
    get manage_contract_path(contract)

    expect(line(response.body, "Payments received")).to eq("$250.00")
    expect(line(response.body, "Payments scheduled out")).to eq("$510.00")
    expect(response.body).not_to include("Deducted from their payouts")
  end
end
