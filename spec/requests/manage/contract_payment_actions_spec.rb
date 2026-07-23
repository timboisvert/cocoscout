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

    it "lets an incoming payment be recorded, with no Venmo/Zelle among the methods" do
      contract = contract_for(payable_person)
      create(:contract_payment, contract: contract, direction: "incoming",
                                status: "pending", amount: 300, amount_tbd: false, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response.body).to include("Record payment")
      expect(response.body).to include("Bank transfer")
      expect(response.body).not_to match(/venmo|zelle|paypal/i)
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

    it "records an incoming payment that arrived offline" do
      contract = contract_for(payable_person)
      payment = create(:contract_payment, contract: contract, direction: "incoming",
                                          status: "pending", amount: 300, amount_tbd: false,
                                          due_date: Date.current)

      post mark_paid_manage_contract_contract_payment_path(contract, payment),
           params: { payment_amount: 300, paid_date: Date.current.to_s, payment_method: "check" }

      expect(payment.reload).to be_status_paid
    end
  end

  it "no longer exposes a flip-direction route (direction comes from the deal)" do
    expect(Rails.application.routes.routes.map { |r| r.name }.compact)
      .not_to include(a_string_matching(/flip_direction/))
  end
end
