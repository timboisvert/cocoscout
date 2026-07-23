# frozen_string_literal: true

require "rails_helper"

# Phase 4 of the contracts redesign: money we owe leaves only through the
# contractor payout run (Stripe, to their bank). Nothing in the contract UI
# offers Venmo or Zelle, and outgoing payments can't be marked paid by hand.
RSpec.describe "Manage contract payment actions", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def payable_person
    person = create(:person)
    person.update!(stripe_account_id: "acct_p#{person.id}", payouts_enabled: true)
    person
  end

  def contract_for(person)
    contractor = create(:contractor, organization: org, person: person, name: "Lighting Co")
    create(:contract, :active, organization: org, production: production,
                               contractor: contractor, contractor_name: contractor.name)
  end

  describe "the payment row" do
    it "offers the payout run for an outgoing payment, never a manual mark-paid" do
      contract = contract_for(payable_person)
      create(:contract_payment, contract: contract, direction: "outgoing",
                                status: "pending", amount: 500, amount_tbd: false, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add to payout run")
      expect(response.body).not_to include("Mark Paid")
      expect(response.body).not_to match(/venmo|zelle/i)
    end

    it "flags a contractor with no connected bank instead of offering the run" do
      contract = contract_for(create(:person))
      create(:contract_payment, contract: contract, direction: "outgoing",
                                status: "pending", amount: 500, amount_tbd: false, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response.body).to include("Needs bank")
      expect(response.body).not_to include("Add to payout run")
    end

    it "says an unsettled ticket-linked payment is waiting on sales" do
      contract = contract_for(payable_person)
      create(:contract_payment, contract: contract, direction: "outgoing", description: "Revenue share",
                                status: "pending", amount: 0, amount_tbd: true, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response.body).to include("Awaiting ticket sales")
      expect(response.body).not_to include("Add to payout run")
    end

    it "leads with the pay link, and still allows a check when the contract does" do
      contract = contract_for(payable_person)
      contract.update_draft_step(:payment_config, { "accepted_payment_methods" => %w[online check] })
      create(:contract_payment, contract: contract, direction: "incoming",
                                status: "pending", amount: 300, amount_tbd: false, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response.body).to include("Copy pay link")
      expect(response.body).to include("Record Payment Received")
      expect(response.body).to include("Check")
      # Only what this contract accepts — no bank transfer, and never Venmo/Zelle.
      expect(response.body).not_to include("Bank transfer")
      expect(response.body).not_to match(/venmo|zelle|paypal/i)
    end

    it "offers only the pay link on an online-only contract" do
      contract = contract_for(payable_person)
      create(:contract_payment, contract: contract, direction: "incoming",
                                status: "pending", amount: 300, amount_tbd: false, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response.body).to include("Copy pay link")
      expect(response.body).not_to include("Record Payment Received")
    end

    it "has nothing to offer on an unsettled incoming amount" do
      contract = contract_for(payable_person)
      create(:contract_payment, contract: contract, direction: "incoming", description: "Revenue share",
                                status: "pending", amount: 0, amount_tbd: true, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response.body).not_to include("Copy pay link")
    end
  end

  describe "POST mark_paid" do
    it "refuses to mark an outgoing payment paid by hand" do
      contract = contract_for(payable_person)
      payment = create(:contract_payment, contract: contract, direction: "outgoing",
                                          status: "pending", amount: 500, amount_tbd: false,
                                          due_date: Date.current)

      post mark_paid_manage_contract_contract_payment_path(contract, payment),
           params: { payment_amount: 500, paid_date: Date.current.to_s }

      expect(payment.reload).to be_status_pending
      expect(flash[:alert]).to include("payout run")
    end

    it "records an incoming payment that arrived by an allowed method" do
      contract = contract_for(payable_person)
      contract.update_draft_step(:payment_config, { "accepted_payment_methods" => %w[online check] })
      payment = create(:contract_payment, contract: contract, direction: "incoming",
                                          status: "pending", amount: 300, amount_tbd: false,
                                          due_date: Date.current)

      post mark_paid_manage_contract_contract_payment_path(contract, payment),
           params: { payment_amount: 300, paid_date: Date.current.to_s, payment_method: "check" }

      expect(payment.reload).to be_status_paid
    end

    it "refuses a method the contract doesn't accept" do
      contract = contract_for(payable_person)
      contract.update_draft_step(:payment_config, { "accepted_payment_methods" => %w[online check] })
      payment = create(:contract_payment, contract: contract, direction: "incoming",
                                          status: "pending", amount: 300, amount_tbd: false,
                                          due_date: Date.current)

      post mark_paid_manage_contract_contract_payment_path(contract, payment),
           params: { payment_amount: 300, paid_date: Date.current.to_s, payment_method: "cash" }

      expect(payment.reload).to be_status_pending
      expect(flash[:alert]).to include("doesn't accept")
    end

    it "refuses to record anything by hand on an online-only contract" do
      contract = contract_for(payable_person)
      payment = create(:contract_payment, contract: contract, direction: "incoming",
                                          status: "pending", amount: 300, amount_tbd: false,
                                          due_date: Date.current)

      post mark_paid_manage_contract_contract_payment_path(contract, payment),
           params: { payment_amount: 300, paid_date: Date.current.to_s, payment_method: "check" }

      expect(payment.reload).to be_status_pending
      expect(flash[:alert]).to include("online payment only")
    end
  end

  describe "the accepted-methods policy" do
    it "inherits the org default and lets a contract override it" do
      org.update!(default_contract_payment_methods: %w[online check])
      contract = contract_for(payable_person)

      expect(contract.accepted_payment_methods).to eq(%w[online check])
      expect(contract).to be_offline_payments_allowed

      contract.update_draft_step(:payment_config, { "accepted_payment_methods" => [ "online" ] })
      expect(contract.reload.offline_payment_methods).to be_empty
      expect(contract).not_to be_offline_payments_allowed
    end

    it "always keeps online available and ignores anything unrecognized" do
      org.update!(default_contract_payment_methods: %w[venmo zelle])
      contract = contract_for(payable_person)

      expect(contract.accepted_payment_methods).to eq([ "online" ])
    end

    it "saves the per-contract choice from the Financials step" do
      contract = create(:contract, organization: org, contractor_name: "Lighting Co", status: "draft")

      post manage_payments_contract_wizard_path(contract), params: {
        payment_structure: "flat_fee",
        payment_config: { flat_fee_amount: 500 }.to_json,
        payments: [].to_json,
        offline_payment_methods: %w[check cash]
      }

      expect(contract.reload.offline_payment_methods).to contain_exactly("check", "cash")
    end

    it "stores the org default from the Contract Settings page" do
      patch manage_contract_settings_payment_methods_path, params: { offline_payment_methods: [ "bank_transfer" ] }

      expect(org.reload.default_contract_payment_methods).to eq(%w[online bank_transfer])
    end
  end

  it "no longer exposes a flip-direction route (direction comes from the deal)" do
    expect(Rails.application.routes.routes.map { |r| r.name }.compact)
      .not_to include(a_string_matching(/flip_direction/))
  end
end
