# frozen_string_literal: true

require "rails_helper"

# Phase 4 of the contracts redesign: money we owe leaves through the contractor
# payout run (Stripe, to their bank) whenever it can. The one exception is a
# contractor a run can't reach — no connected bank — who has to be paid by hand;
# there the org's own offline methods (Money settings) are offered, and only
# there.
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

    it "shows the net amount actually paid when services deduct from a settlement" do
      contract = contract_for(payable_person)
      create(:contract_payment, contract: contract, direction: "outgoing", description: "Aug 9 — 50% to them",
                                status: "pending", amount: 257.50, amount_tbd: false, due_date: Date.new(2026, 8, 9))
      create(:contract_payment, contract: contract, direction: "incoming", description: "Booth Tech — Aug 9, 2026",
                                status: "paid", paid_date: Date.new(2026, 8, 9), amount: 50,
                                settlement_method: "payout_deduction", payment_method: "payout_deduction",
                                due_date: Date.new(2026, 8, 9))

      get manage_contract_path(contract)

      expect(response).to have_http_status(:ok)
      # The big number is what actually moves; the gross and deduction sit under it.
      expect(response.body).to include("$207.50")
      expect(response.body).to include("$257.50 − $50.00 services")
      expect(response.body).to include("1 charge deducted from this payment")
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
      # Recording lists every way money arrives; the contract's own methods lead.
      expect(response.body).to include("Check")
      expect(response.body).to include("Zelle")
    end

    it "still lets money be recorded on an online-only contract" do
      # Online-only is what the payer is told, not a bar on recording what came in.
      contract = contract_for(payable_person)
      create(:contract_payment, contract: contract, direction: "incoming",
                                status: "pending", amount: 300, amount_tbd: false, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response.body).to include("Copy pay link")
      expect(response.body).to include("Record Payment Received")
    end

    it "has nothing to offer on an unsettled incoming amount" do
      contract = contract_for(payable_person)
      create(:contract_payment, contract: contract, direction: "incoming", description: "Revenue share",
                                status: "pending", amount: 0, amount_tbd: true, due_date: Date.current)

      get manage_contract_path(contract)

      expect(response.body).not_to include("Copy pay link")
    end
  end

  describe "PATCH settlement (pay directly vs deduct from payout)" do
    let(:contract) { contract_for(payable_person) }
    let!(:service) do
      create(:contract_payment, contract: contract, direction: "incoming",
                                amount: 120, description: "Tech service")
    end
    # The share this charge nets out of. Without money going the other way there
    # is no payout to deduct from at all.
    let!(:settlement) do
      create(:contract_payment, :outgoing, contract: contract, amount: 800,
                                           description: "Revenue Share Settlement")
    end

    it "flips a pending incoming payment to deduct-from-payout and back" do
      patch settlement_manage_contract_contract_payment_path(contract, service, settlement_method: "payout_deduction")
      expect(service.reload.settlement_method).to eq("payout_deduction")
      expect(service).not_to be_collectable_online

      patch settlement_manage_contract_contract_payment_path(contract, service, settlement_method: "direct")
      expect(service.reload.settlement_method).to eq("direct")
      expect(service).to be_collectable_online
    end

    it "refuses on outgoing or already-paid payments" do
      outgoing = create(:contract_payment, :outgoing, contract: contract, amount: 50)
      patch settlement_manage_contract_contract_payment_path(contract, outgoing, settlement_method: "payout_deduction")
      expect(outgoing.reload.settlement_method).to eq("direct")

      service.update!(status: "paid", paid_date: Date.current)
      patch settlement_manage_contract_contract_payment_path(contract, service, settlement_method: "payout_deduction")
      expect(service.reload.settlement_method).to eq("direct")
    end

    it "folds the charge into its settlement instead of offering pay-link actions" do
      service.update!(settlement_method: "payout_deduction")
      get manage_contract_path(contract)
      expect(response.body).to include("charge deducted from this payment")
      expect(response.body).not_to include("Copy pay link")
    end

    it "offers the pay link again once every settlement has gone out" do
      # Nothing left to net against: the charge is an ordinary invoice now, and
      # must not sit as a "deducts from payout" that can never happen.
      settlement.update!(status: "paid", paid_date: Date.current)
      service.update!(settlement_method: "payout_deduction")

      get manage_contract_path(contract)

      expect(response.body).not_to include("Deducts from payout")
      expect(response.body).to include("Copy pay link")
    end

    it "renders a cancelled payment muted, marked, and with no actions" do
      # Cancelling a contract cancels its pending payments; that history stays
      # on the page but must read as history — never as money still moving.
      service.update!(status: "cancelled")
      get manage_contract_path(contract)

      expect(response.body).to include("Cancelled")
      expect(response.body).to include("line-through")
      expect(response.body).not_to include("Copy pay link")
    end

    it "refuses to deduct on a contract with no payout going out" do
      settlement.destroy
      patch settlement_manage_contract_contract_payment_path(contract, service, settlement_method: "payout_deduction")

      expect(service.reload.settlement_method).to eq("direct")
      expect(flash[:alert]).to include("no payout to deduct from")
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

    it "records money however it actually arrived, whatever the contract told them" do
      # The accepted methods are what the PAYER is shown; a Zelle that already
      # landed is a fact and gets recorded — on an online-only contract too.
      contract = contract_for(payable_person)
      payment = create(:contract_payment, contract: contract, direction: "incoming",
                                          status: "pending", amount: 300, amount_tbd: false,
                                          due_date: Date.current)

      post mark_paid_manage_contract_contract_payment_path(contract, payment),
           params: { payment_amount: 300, paid_date: Date.current.to_s, payment_method: "zelle" }

      expect(payment.reload).to be_status_paid
      expect(payment.payment_method).to eq("zelle")
    end

    it "still refuses a method that isn't a way money arrives" do
      contract = contract_for(payable_person)
      payment = create(:contract_payment, contract: contract, direction: "incoming",
                                          status: "pending", amount: 300, amount_tbd: false,
                                          due_date: Date.current)

      post mark_paid_manage_contract_contract_payment_path(contract, payment),
           params: { payment_amount: 300, paid_date: Date.current.to_s, payment_method: "bitcoin" }

      expect(payment.reload).to be_status_pending
      expect(flash[:alert]).to include("Unknown payment method")
    end

    it "agrees with the Collect page: both record the same Zelle" do
      contract = contract_for(payable_person)
      payment = create(:contract_payment, contract: contract, direction: "incoming",
                                          status: "pending", amount: 300, amount_tbd: false,
                                          due_date: Date.current)

      post manage_mark_received_money_incoming_payment_path(payment),
           params: { payment_amount: 300, paid_date: Date.current.to_s, payment_method: "zelle" }

      expect(payment.reload).to be_status_paid
      expect(payment.payment_method).to eq("zelle")
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
      org.update!(default_contract_payment_methods: %w[bitcoin paypal])
      contract = contract_for(payable_person)

      expect(contract.accepted_payment_methods).to eq([ "online" ])
    end

    it "lets a contract tell the payer they may use Zelle or Venmo" do
      contract = contract_for(payable_person)
      contract.update_draft_step(:payment_config, { "accepted_payment_methods" => %w[online zelle check] })

      expect(contract.offline_payment_methods).to eq(%w[zelle check])
      expect(contract.offline_payment_methods_sentence).to eq("Zelle or check")
    end

    it "tells the payer nothing but CocoScout when the contract is online-only" do
      contract = contract_for(payable_person)
      expect(contract.offline_payment_methods_sentence).to be_nil
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

  # Paying someone who never connected a bank: the run can't reach them, so the
  # money goes out by hand and has to be recordable, or the payment stays due
  # forever.
  describe "POST pay_offline" do
    before { org.update!(enabled_offline_payout_methods: %w[zelle check]) }

    let(:contract) { contract_for(create(:person)) }
    let(:payment) do
      create(:contract_payment, contract: contract, direction: "outgoing", description: "Revenue Share - Event 6",
                                status: "pending", amount: 40, amount_tbd: false, due_date: Date.current)
    end

    it "offers it on the row for a contractor with no bank" do
      payment
      get manage_contract_path(contract)

      expect(response.body).to include("Needs bank")
      expect(response.body).to include("Paid another way")
      expect(response.body).to include("Zelle")
    end

    it "stays off the row for a contractor who can be paid on a run" do
      payable = contract_for(payable_person)
      create(:contract_payment, contract: payable, direction: "outgoing",
                                status: "pending", amount: 40, amount_tbd: false, due_date: Date.current)

      get manage_contract_path(payable)

      expect(response.body).to include("Add to payout run")
      expect(response.body).not_to include("Paid another way")
    end

    it "stays off the row when the org hasn't turned on any offline method" do
      org.update!(enabled_offline_payout_methods: [])
      payment
      get manage_contract_path(contract)

      expect(response.body).to include("Needs bank")
      expect(response.body).not_to include("Paid another way")
    end

    it "records the payment paid, with no ledger entry and no payout run" do
      expect {
        post pay_offline_manage_contract_contract_payment_path(contract, payment),
             params: { payment_method: "zelle", paid_date: Date.current.to_s, payment_notes: "Zelle #4471" }
      }.not_to change(PayoutLedgerEntry, :count)

      expect(payment.reload).to be_status_paid
      expect(payment.payment_method).to eq("zelle")
      expect(payment.reference_number).to eq("Zelle #4471")
      expect(payment).to be_paid_offline
      expect(payment.payout_contribution).to be_nil
      expect(flash[:notice]).to include("$40.00")
    end

    it "refuses a method the org doesn't pay with" do
      post pay_offline_manage_contract_contract_payment_path(contract, payment),
           params: { payment_method: "venmo", paid_date: Date.current.to_s }

      expect(payment.reload).to be_status_pending
      expect(flash[:alert]).to include("doesn't pay people by venmo")
    end

    it "refuses money they owe us" do
      incoming = create(:contract_payment, contract: contract, direction: "incoming",
                                           status: "pending", amount: 40, amount_tbd: false, due_date: Date.current)

      post pay_offline_manage_contract_contract_payment_path(contract, incoming),
           params: { payment_method: "zelle" }

      expect(incoming.reload).to be_status_pending
      expect(flash[:alert]).to include("Collect page")
    end

    it "refuses a payment with no amount set yet" do
      tbd = create(:contract_payment, contract: contract, direction: "outgoing",
                                      status: "pending", amount: 0, amount_tbd: true, due_date: Date.current)

      post pay_offline_manage_contract_contract_payment_path(contract, tbd), params: { payment_method: "zelle" }

      expect(tbd.reload).to be_status_pending
      expect(flash[:alert]).to include("Set an amount")
    end

    it "settles the services that were waiting to net out of it" do
      payment.update!(amount: 257.50, due_date: Date.new(2026, 8, 9))
      service = create(:contract_payment, contract: contract, direction: "incoming", description: "Booth Tech",
                                          status: "pending", amount: 50, amount_tbd: false,
                                          settlement_method: "payout_deduction", due_date: Date.new(2026, 8, 9))

      post pay_offline_manage_contract_contract_payment_path(contract, payment),
           params: { payment_method: "zelle", paid_date: Date.new(2026, 8, 9).to_s }

      expect(payment.reload).to be_status_paid
      expect(service.reload).to be_status_paid
      expect(service.payment_method).to eq("payout_deduction")
      # What actually left the org is the share net of the service.
      expect(flash[:notice]).to include("$207.50")
    end

    it "refuses when the services come to more than the payment" do
      create(:contract_payment, contract: contract, direction: "incoming", description: "Booth Tech",
                                status: "pending", amount: 60, amount_tbd: false,
                                settlement_method: "payout_deduction", due_date: payment.due_date)

      post pay_offline_manage_contract_contract_payment_path(contract, payment), params: { payment_method: "zelle" }

      expect(payment.reload).to be_status_pending
      expect(flash[:alert]).to include("nothing to hand over")
    end
  end

  it "no longer exposes a flip-direction route (direction comes from the deal)" do
    expect(Rails.application.routes.routes.map { |r| r.name }.compact)
      .not_to include(a_string_matching(/flip_direction/))
  end
end
