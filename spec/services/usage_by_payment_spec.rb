# frozen_string_literal: true

require "rails_helper"

# From November 2026 usage counts everyone an organization pays through
# CocoScout in a month, by the month it reaches their bank (how Stripe charges
# CocoScout for paying them), and bank debits beyond two a month are $5 each
# on the usage bill (Tim, 2026-11-01).
RSpec.describe "Usage by the month people are paid", type: :request do
  let(:org) { create(:organization, :pro, stripe_customer_id: "cus_sg", funding_payment_method_type: "us_bank_account") }
  let(:november) { Date.new(2026, 11, 1) }

  def pay(person, sent:, deposited: nil, staff: false, through_stripe: true)
    batch = org.payout_batches.create!(kind: "payout", status: "completed", trigger: "manual", total_cents: 10_000)
    item = batch.items.create!(payee: person, amount_cents: 10_000, status: "pending")
    PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: person, amount_cents: 10_000,
                               label: staff ? "Shifts" : "Show pay", category: staff ? "staffing" : "performer")
    item.update_columns(status: "paid", paid_at: sent, deposited_at: deposited, stripe_transfer_id: through_stripe ? "tr_#{item.id}" : nil)
    item
  end

  def fund_run(at)
    org.payout_batches.create!(kind: "payout", status: "completed", trigger: "manual", total_cents: 50_000,
                               funding_payment_intent_id: "pi_#{SecureRandom.hex(4)}", funding_status: "succeeded", funding_started_at: at)
  end

  it "counts everyone paid in the month by when it reached their bank: staff at $5, everyone else at $3" do
    ruby, ana, contractor, late, by_hand = create_list(:person, 5)
    pay(ruby, sent: Time.zone.local(2026, 11, 6), staff: true)
    pay(ruby, sent: Time.zone.local(2026, 11, 13))
    pay(ana, sent: Time.zone.local(2026, 11, 6), deposited: Time.zone.local(2026, 11, 8))
    pay(contractor, sent: Time.zone.local(2026, 11, 20))
    # Sent on the 30th, in their bank on December 2: December's.
    pay(late, sent: Time.zone.local(2026, 11, 30, 15), deposited: Time.zone.local(2026, 12, 2, 9))
    # Paid another way, not through Stripe: nothing to bill.
    pay(by_hand, sent: Time.zone.local(2026, 11, 10), through_stripe: false)

    expect(UsageRules.staff(november).fetch(org.id).keys).to eq([ ruby.id ])
    expect(UsageRules.performers(november).fetch(org.id).keys).to contain_exactly(ana.id, contractor.id)
    expect(UsageRules.performers(Date.new(2026, 12, 1)).fetch(org.id).keys).to eq([ late.id ])
  end

  it "doesn't bill anyone in November whom October's bill already counted" do
    october_performer, newcomer = create_list(:person, 2)
    PerformerActivation.record!(organization: org, person: october_performer, month: Date.new(2026, 10, 1))
    pay(october_performer, sent: Time.zone.local(2026, 11, 3))
    pay(newcomer, sent: Time.zone.local(2026, 11, 3))
    expect(UsageRules.performers(november).fetch(org.id).keys).to eq([ newcomer.id ])

    pay(october_performer, sent: Time.zone.local(2026, 12, 3))
    expect(UsageRules.performers(Date.new(2026, 12, 1)).fetch(org.id).keys).to eq([ october_performer.id ])
  end

  it "keeps October and before on the month the work happened" do
    person = create(:person)
    pay(person, sent: Time.zone.local(2026, 10, 9))
    expect(UsageRules.performers(Date.new(2026, 10, 1), now: Time.zone.local(2026, 11, 1))).to eq({})
  end

  it "gives two bank debits a month free, then $5 each, and none to an organization funding by card" do
    fund_run(Time.zone.local(2026, 11, 2))
    fund_run(Time.zone.local(2026, 11, 9))
    expect(UsageRules.extra_bank_debits(org, november)).to eq(0)
    fund_run(Time.zone.local(2026, 11, 16))
    BalanceTopUp.create!(organization: org, amount_cents: 20_000, status: "succeeded", stripe_payment_intent_id: "pi_top", created_at: Time.zone.local(2026, 11, 20))
    expect([ UsageRules.extra_bank_debits(org, november), UsageRules.bank_debit_fee_cents(org, november) ]).to eq([ 2, 1_000 ])
    # A run paid from the balance, with no debit, doesn't count; neither does October.
    org.payout_batches.create!(kind: "payout", status: "completed", trigger: "manual", total_cents: 1_000, created_at: Time.zone.local(2026, 11, 21))
    expect(UsageRules.extra_bank_debits(org, november)).to eq(2)
    expect(UsageRules.extra_bank_debits(org, Date.new(2026, 10, 1))).to eq(0)

    org.update!(funding_payment_method_type: "card")
    expect(UsageRules.extra_bank_debits(org, november)).to eq(0)
  end

  it "puts the extra debits on the month's bill, and on our invoice, counted as owed" do
    staffer, performer = create_list(:person, 2)
    pay(staffer, sent: Time.zone.local(2026, 11, 6), staff: true)
    pay(performer, sent: Time.zone.local(2026, 11, 6))
    UsageRebuild.run!(november, post: true, now: Time.zone.local(2026, 12, 1))
    3.times { |i| fund_run(Time.zone.local(2026, 11, 2 + i)) }
    record = BillingInvoice.create!(organization: org, stripe_invoice_id: "in_nov", kind: "usage", status: "draft", amount_due_cents: 800,
                                    period_start: Time.zone.local(2026, 11, 1), period_end: Time.zone.local(2026, 12, 1),
                                    lines: [ { "description" => "usage", "amount_cents" => 800 } ])
    expect(Stripe::InvoiceItem).to receive(:create)
      .with(hash_including(invoice: "in_nov", amount: 500, description: "1 bank debit beyond the 2 free in November 2026, $5 each"),
            hash_including(idempotency_key: "bank-debit-fee-in_nov-1"))
    UsageInvoiceCorrection.apply!(record)

    record.update!(status: "paid", amount_due_cents: 1_300, amount_paid_cents: 1_300, lines: [ { "description" => "usage", "amount_cents" => 800 }, { "description" => "fee", "amount_cents" => 500 } ])
    lines = CocoScoutInvoice.document(record).items.map { |line| [ line.description, line.amount_cents ] }
    expect(lines).to eq([ [ "1 staff member paid × $5.00", 500 ], [ "1 other person paid × $3.00", 300 ], [ "1 bank debit beyond the 2 free × $5.00", 500 ] ])

    expect(UsageOverbilling.rows(org).sole.over_cents).to eq(0)
  end

  it "shows a Pro organization its usage, bank debits and bills on the Billing tab" do
    travel_to Time.zone.local(2026, 11, 20, 10) do
      manager = create(:user, password: "Password123!")
      create(:person, user: manager)
      org.update!(owner: manager)
      create(:organization_role, :manager, user: manager, organization: org)
      PerformerActivation.record!(organization: org, person: create(:person, name: "Avery Lane"), month: november)
      3.times { |i| fund_run(Time.zone.local(2026, 11, 2 + i)) }
      post handle_signin_path, params: { email_address: manager.email_address, password: "Password123!" }
      get manage_path
      get section_manage_organization_path(org, section: "billing")
      expect(response.body).to include("usage</h4>", "Everyone else paid", "Avery Lane", "Bank debits", "of 2 free",
                                       "1 extra debit", "$8.00", "billed Dec 1", "Payout run funded from your bank")
      expect(response.body).not_to include("Stripe")
    end
  end
end
