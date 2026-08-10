# frozen_string_literal: true

require "rails_helper"

# Amending a contract must never invent money.
#
# The bug this exists to prevent: a weekly revenue-share deal was amended to
# cancel one date. reconcile_amended_payments! destroyed every pending payment
# and rebuilt the whole schedule from the deal, which produced a *second*
# payment for June 4 — a show that had already happened, already sold tickets
# and already been paid $63. The paid one survived (it wasn't pending), so the
# contract showed the paid $63 beside a phantom TBD marked "2 months overdue".
RSpec.describe "Contract payment reconciliation", type: :model do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) { create(:contract, :active, organization: org, production: production) }

  # What the Financials editor stages: the deal regenerated across every date,
  # past ones included.
  def staged(description:, due_date:, direction: "outgoing", amount: 0, tbd: true, notes: nil)
    { "description" => description, "due_date" => due_date.to_s, "direction" => direction,
      "amount" => amount, "amount_tbd" => tbd, "notes" => notes }
  end

  describe "dates that already carry settled money" do
    it "does not create a second payment for a date that's already been paid" do
      paid = contract.contract_payments.create!(
        description: "Revenue Share - Event 1 (40% to them)", amount: 63, direction: "outgoing",
        due_date: Date.new(2026, 6, 4), status: "paid", paid_date: Date.new(2026, 6, 4)
      )

      contract.reconcile_amended_payments!([
        staged(description: "Jun 4 — 60% to them", due_date: Date.new(2026, 6, 4)),
        staged(description: "Jul 2 — 60% to them", due_date: Date.new(2026, 7, 2))
      ])

      june = contract.contract_payments.reload.where(due_date: Date.new(2026, 6, 4))
      expect(june.count).to eq(1)
      expect(june.first).to eq(paid)
      expect(june.first.amount).to eq(63)
      # The date that isn't settled still gets its payment.
      expect(contract.contract_payments.where(due_date: Date.new(2026, 7, 2)).count).to eq(1)
    end

    it "does not create a second payment for a date already committed to a payout run" do
      committed = contract.contract_payments.create!(
        description: "Aug 6 — 60% to them", amount: 100, direction: "outgoing",
        due_date: Date.new(2026, 8, 6)
      )
      payee = create(:person)
      batch = PayoutBatch.create!(organization: org, status: "draft", kind: "performer")
      item = batch.items.create!(payee: payee, amount_cents: 10_000)
      batch.payout_contributions.create!(source: committed, payout_batch_item: item,
                                         payee: payee, amount_cents: 10_000, label: "Settlement")

      contract.reconcile_amended_payments!([
        staged(description: "Aug 6 — 55% to them", due_date: Date.new(2026, 8, 6), amount: 90, tbd: false)
      ])

      august = contract.contract_payments.reload.where(due_date: Date.new(2026, 8, 6))
      expect(august.count).to eq(1)
      # Untouched: the run already owns this amount.
      expect(august.first.id).to eq(committed.id)
      expect(august.first.amount).to eq(100)
    end
  end

  describe "matching an existing payment instead of replacing it" do
    it "re-prices in place and keeps the id, so links and history survive" do
      original = contract.contract_payments.create!(
        description: "Ticket revenue less $750.00 fee — week of Nov 2", amount: 0, amount_tbd: true,
        direction: "outgoing", due_date: Date.new(2026, 11, 7)
      )

      contract.reconcile_amended_payments!([
        staged(description: "Ticket revenue less $800.00 fee — week of Nov 2", due_date: Date.new(2026, 11, 7))
      ])

      expect(contract.contract_payments.reload.count).to eq(1)
      kept = contract.contract_payments.first
      expect(kept.id).to eq(original.id)
      expect(kept.description).to include("$800.00")
    end

    it "keeps a hand-set settlement choice through an amendment" do
      contract.contract_payments.create!(
        description: "Booth Tech", amount: 50, direction: "incoming",
        due_date: Date.new(2026, 11, 5), settlement_method: "payout_deduction"
      )

      contract.reconcile_amended_payments!([
        staged(description: "Booth Tech", due_date: Date.new(2026, 11, 5),
               direction: "incoming", amount: 75, tbd: false)
      ])

      payment = contract.contract_payments.reload.first
      expect(payment.amount).to eq(75)          # the deal's field changed
      expect(payment.settlement_method).to eq("payout_deduction")  # the manager's did not
    end

    it "keeps an already-issued pay link" do
      payment = contract.contract_payments.create!(
        description: "Rental fee", amount: 500, direction: "incoming", due_date: Date.new(2026, 12, 1)
      )
      token = payment.payment_token!

      contract.reconcile_amended_payments!([
        staged(description: "Rental fee", due_date: Date.new(2026, 12, 1),
               direction: "incoming", amount: 550, tbd: false)
      ])

      expect(contract.contract_payments.reload.first.payment_token).to eq(token)
    end
  end

  describe "dates the amended deal no longer produces" do
    it "drops the pending payment for a removed date" do
      contract.contract_payments.create!(description: "Nov 5 — 60% to them", amount: 0, amount_tbd: true,
                                         direction: "outgoing", due_date: Date.new(2026, 11, 5))
      contract.contract_payments.create!(description: "Nov 6 — 60% to them", amount: 0, amount_tbd: true,
                                         direction: "outgoing", due_date: Date.new(2026, 11, 6))

      contract.reconcile_amended_payments!([
        staged(description: "Nov 5 — 60% to them", due_date: Date.new(2026, 11, 5))
      ])

      expect(contract.contract_payments.reload.pluck(:due_date)).to eq([ Date.new(2026, 11, 5) ])
    end

    it "never destroys a paid payment, even when the deal drops its date" do
      contract.contract_payments.create!(description: "Deposit", amount: 200, direction: "incoming",
                                         due_date: Date.new(2026, 5, 1), status: "paid",
                                         paid_date: Date.new(2026, 5, 1))

      contract.reconcile_amended_payments!([])

      expect(contract.contract_payments.reload.count).to eq(1)
      expect(contract.contract_payments.first.status).to eq("paid")
    end
  end

  describe "relinking payments to shows after an amendment" do
    # The Pavlov bug: a per-event revenue-share run whose first show had
    # already been paid. The amendment relinks only PENDING payments, but the
    # old code paired them positionally against the FULL show list — so every
    # payment linked to the show one slot back, and the financials sync then
    # wrote the Aug 9 show's share onto the Sep 13 payment.
    it "links each pending payment to the show on its due date, not the neighbor's" do
      contract.update!(draft_data: {
        "payment_structure" => "revenue_share",
        "payment_config" => { "revenue_settlement" => "per_event",
                              "revenue_our_share" => 50.0, "revenue_their_share" => 50.0,
                              "who_sells_tickets" => "us" }
      })
      jul = create(:show, production: production, date_and_time: Time.zone.local(2026, 7, 12, 20))
      aug = create(:show, production: production, date_and_time: Time.zone.local(2026, 8, 9, 20))
      sep = create(:show, production: production, date_and_time: Time.zone.local(2026, 9, 13, 20))

      contract.contract_payments.create!(
        description: "Revenue Share - Event 1 (50% to them)", amount: 320, direction: "outgoing",
        due_date: Date.new(2026, 7, 12), status: "paid", paid_date: Date.new(2026, 7, 14), show: jul
      )

      contract.reconcile_amended_payments!([
        staged(description: "Aug 9 — 50% to them", due_date: Date.new(2026, 8, 9)),
        staged(description: "Sep 13 — 50% to them", due_date: Date.new(2026, 9, 13))
      ])

      aug_payment = contract.contract_payments.reload.find_by(due_date: Date.new(2026, 8, 9))
      sep_payment = contract.contract_payments.find_by(due_date: Date.new(2026, 9, 13))
      expect(aug_payment.show_id).to eq(aug.id)
      expect(sep_payment.show_id).to eq(sep.id)

      # And the money lands on the right payment: Aug 9's financials settle
      # the Aug 9 payment, while Sep 13 stays awaiting its own ticket sales.
      create(:show_financials, show: aug, ticket_count: 32, ticket_revenue: 515.0, expenses: 0)
      ContractPaymentSyncService.new(aug.reload).call

      expect(aug_payment.reload.amount.to_f).to eq(257.50)
      expect(aug_payment.amount_tbd).to be(false)
      expect(sep_payment.reload.amount_tbd).to be(true)
    end

    it "leaves a link the payment already carries alone" do
      contract.update!(draft_data: {
        "payment_structure" => "revenue_share",
        "payment_config" => { "revenue_settlement" => "per_event",
                              "revenue_our_share" => 50.0, "revenue_their_share" => 50.0 }
      })
      aug = create(:show, production: production, date_and_time: Time.zone.local(2026, 8, 9, 20))
      payment = contract.contract_payments.create!(
        description: "Aug 9 — 50% to them", amount: 0, amount_tbd: true,
        direction: "outgoing", due_date: Date.new(2026, 8, 9), show: aug
      )

      contract.reconcile_amended_payments!([
        staged(description: "Aug 9 — 55% to them", due_date: Date.new(2026, 8, 9))
      ])

      expect(payment.reload.show_id).to eq(aug.id)
      expect(payment.description).to include("55%")
    end
  end

  describe "amending services and payments together" do
    # The booth-tech bug: one amendment added a per-show service AND carried a
    # staged payment list. apply_amendment! billed the service, then
    # reconcile_amended_payments! — whose staged list predates the billing —
    # saw the fresh charges as rows the deal no longer produces and destroyed
    # them moments after creating them.
    it "keeps the service charges billed by the same amendment" do
      contract.update!(draft_data: {
        "payment_structure" => "revenue_share",
        "payment_config" => { "revenue_settlement" => "per_event",
                              "revenue_our_share" => 50.0, "revenue_their_share" => 50.0 }
      })
      create(:show, production: production, date_and_time: Time.zone.local(2026, 8, 9, 20))

      contract.apply_amendment!({
        "services" => [
          { "name" => "Booth Tech", "unit" => "flat", "unit_price" => 50.0,
            "direction" => "incoming", "settlement" => "direct", "per_event" => true,
            "events" => [ { "starts_at" => "2026-08-09T20:00:00", "hours" => 1 } ] }
        ],
        "payments" => [
          staged(description: "Aug 9 — 50% to them", due_date: Date.new(2026, 8, 9))
        ]
      })

      payments = contract.contract_payments.reload
      booth = payments.find { |p| p.description.start_with?("Booth Tech") }
      expect(booth).to be_present
      expect(booth.amount.to_f).to eq(50.0)
      expect(booth.direction).to eq("incoming")
      expect(payments.map(&:description)).to include("Aug 9 — 50% to them")
    end

    it "protects existing service charges from an amendment that only touches payments" do
      contract.update_draft_step(:services, [
        { "name" => "Booth Tech", "unit" => "flat", "unit_price" => 50.0,
          "direction" => "incoming", "quantity" => 1 }
      ])
      charge = contract.contract_payments.create!(
        description: "Booth Tech — Aug 9, 2026", amount: 50, direction: "incoming",
        due_date: Date.new(2026, 8, 9)
      )

      contract.reconcile_amended_payments!([
        staged(description: "Aug 9 — 50% to them", due_date: Date.new(2026, 8, 9))
      ])

      expect(contract.contract_payments.reload.ids).to include(charge.id)
    end
  end

  describe "re-billing services on an amendment" do
    it "does not raise a service charge that was already paid" do
      contract.update_draft_step(:services, [])
      contract.contract_payments.create!(
        description: "Booth Tech — Nov 5, 2026", amount: 50, direction: "incoming",
        due_date: Date.new(2026, 11, 5), status: "paid", paid_date: Date.new(2026, 11, 5)
      )

      contract.reconcile_service_payments!([
        { "name" => "Booth Tech", "unit" => "hourly", "unit_price" => 25, "direction" => "incoming",
          "settlement" => "payout_deduction", "per_event" => true,
          "events" => [ { "starts_at" => "2026-11-05T20:00:00", "hours" => 2 },
                        { "starts_at" => "2026-11-06T20:00:00", "hours" => 2 } ] }
      ])

      charges = contract.contract_payments.reload.where("description LIKE ?", "Booth Tech%")
      expect(charges.where(due_date: Date.new(2026, 11, 5)).count).to eq(1)
      expect(charges.find_by(due_date: Date.new(2026, 11, 5)).status).to eq("paid")
      # The unbilled date still gets its charge.
      expect(charges.where(due_date: Date.new(2026, 11, 6)).count).to eq(1)
    end
  end
end
