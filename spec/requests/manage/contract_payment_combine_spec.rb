# frozen_string_literal: true

require "rails_helper"

# Combining a contract's small invoices into one payment, and splitting them
# back out, from the contract page.
RSpec.describe "Manage::ContractPayments combine and split", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:contract) { create(:contract, :active, organization: org) }

  let!(:event_payment) do
    create(:contract_payment, contract: contract, description: "Event fee",
                              amount: 600.0, due_date: Date.new(2026, 10, 19))
  end
  let!(:rehearsal) do
    create(:contract_payment, contract: contract, description: "Rehearsal — Sep 10, 2026",
                              amount: 100.0, due_date: Date.new(2026, 9, 10))
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "combines the checked payments into the host, then splits them back out" do
    post combine_manage_contract_contract_payment_path(contract, event_payment),
         params: { payment_ids: [ rehearsal.id ] }

    expect(response).to redirect_to(manage_contract_path(contract))
    expect(flash[:notice]).to include("Combined 2 payments into one $700.00 payment due Oct 19, 2026")
    expect(contract.contract_payments.count).to eq(1)
    expect(event_payment.reload.amount.to_f).to eq(700.0)

    post split_manage_contract_contract_payment_path(contract, event_payment)

    expect(response).to redirect_to(manage_contract_path(contract))
    expect(event_payment.reload.amount.to_f).to eq(600.0)
    restored = contract.contract_payments.find_by(description: "Rehearsal — Sep 10, 2026")
    expect(restored.amount.to_f).to eq(100.0)
    expect(restored.due_date).to eq(Date.new(2026, 9, 10))
  end

  it "refuses a payment that isn't combinable, without touching anything" do
    rehearsal.update!(status: "paid", paid_date: Date.current)

    post combine_manage_contract_contract_payment_path(contract, event_payment),
         params: { payment_ids: [ rehearsal.id ] }

    expect(response).to redirect_to(manage_contract_path(contract))
    expect(flash[:alert]).to include("Could not combine")
    expect(event_payment.reload.amount.to_f).to eq(600.0)
    expect(contract.contract_payments.count).to eq(2)
  end

  it "offers Combine (and its modal) when the contract holds other pending payments" do
    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Combine payments")
    expect(response.body).to include("combine-payment-#{event_payment.id}")
    expect(response.body).to include("payment_ids[]")
  end

  it "shows a late payment as the pink wash plus the overdue line — no Late badge" do
    rehearsal.update!(due_date: 2.weeks.ago)

    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("bg-pink-50 border-pink-300")
    expect(response.body).to include("overdue")
    expect(response.body).not_to include(">Late<")
  end

  it "renders the contract page with the combined row and its breakdown" do
    event_payment.merge_in!([ rehearsal ])

    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("incl. Rehearsal — Sep 10, 2026 $100.00")
    expect(response.body).to include("Split combined payments")
  end
end
