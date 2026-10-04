# frozen_string_literal: true

require "rails_helper"

# Books stage B: every row of the two sub-ledgers lands in the books from the
# row itself, so the "CocoScout balance" account always equals the cash
# ledger and "Owed to performers and staff" always equals the payout ledger —
# and the books still balance.
RSpec.describe BooksPoster do
  let(:org) { create(:organization, :pro, stripe_account_id: "acct_sg", payouts_enabled: true) }

  def balance(key)
    ChartOfAccounts.account(org, key).natural_balance_cents
  end

  def books_balance_rows
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    expect(balance(:cocoscout_balance)).to eq(OrgCashEntry.where(organization: org).sum(:amount_cents))
    # A positive payout-ledger sum is money owed: the liability's natural balance.
    expect(balance(:owed_to_payees)).to eq(PayoutLedgerEntry.where(organization: org).sum(:amount_cents))
  end

  describe "the cash ledger" do
    let(:production) { create(:production, organization: org, production_type: "course") }
    let(:offering) { create(:course_offering, production: production, price_cents: 10_000) }

    it "posts a course sale as income, tax and fees, and takes it back on refund" do
      TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "10", mode: "added")
      registration = offering.course_registrations.create!(
        person: create(:person), status: :confirmed, amount_cents: 10_000, tax_cents: 1_000, currency: "usd",
        registered_at: Time.current, paid_at: Time.current, stripe_checkout_session_id: "cs_b", stripe_payment_intent_id: "pi_b",
        cocoscout_fee_cents: 1_000
      )
      # Net = 10,000 − 1,000 fee + 1,000 tax.
      expect(balance(:cocoscout_balance)).to eq(10_000)
      expect(balance(:course_income)).to eq(10_000)
      expect(balance(:tax_to_remit)).to eq(1_000)
      expect(balance(:course_fees)).to eq(1_000)
      books_balance_rows

      allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_b"))
      CourseRegistrationRefundService.call(registration)
      expect(balance(:cocoscout_balance)).to eq(0)
      expect(balance(:course_income)).to eq(0)
      expect(balance(:tax_to_remit)).to eq(0)
      books_balance_rows
    end

    it "posts funding, a payee paid, a return, and corrections" do
      batch = PayoutBatch.create!(organization: org, status: "draft")
      OrgCashEntry.post!(organization: org, entry_type: "funding", amount_cents: 50_000, source: batch, description: "Funding")
      expect(balance(:bank)).to eq(-50_000)
      expect(balance(:cocoscout_balance)).to eq(50_000)

      payee = create(:person)
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: 20_000, description: "Show pay")
      item = batch.items.create!(payee: payee, amount_cents: 20_000, status: "pending")
      OrgCashEntry.post!(organization: org, entry_type: "transfer", amount_cents: -20_000, source: item, description: "Paid")
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "payout", amount_cents: -20_000, source: item)
      expect(balance(:owed_to_payees)).to eq(0)
      expect(balance(:cocoscout_balance)).to eq(30_000)

      org_item = batch.items.create!(payee: org, amount_cents: 5_000, status: "pending")
      OrgCashEntry.post!(organization: org, entry_type: "transfer", amount_cents: -5_000, source: org_item, description: "Remitted")
      expect(balance(:bank)).to eq(-45_000)

      OrgCashEntry.post!(organization: org, entry_type: "adjustment", amount_cents: -1_000, description: "Superadmin fix")
      OrgCashEntry.post!(organization: org, entry_type: "opening_balance", amount_cents: 2_500, description: "Opening")
      expect(balance(:owner_equity)).to eq(1_500)
      books_balance_rows

      # A failed transfer unposts both rows; the books follow.
      OrgCashEntry.unpost!(source: item, entry_type: "transfer")
      PayoutLedgerEntry.unpost!(source: item, entry_type: "payout")
      expect(balance(:owed_to_payees)).to eq(20_000)
      books_balance_rows
    end

    it "leaves ticketing's own posts alone" do
      listing = create(:ticket_listing, organization: org)
      tier = listing.ticket_tiers.create!(name: "General", price_cents: 2_000)
      order = TicketCheckout.start!(listing: listing, quantities: { tier.id.to_s => "1" })
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_t")
      expect(JournalEntry.where(organization: org, kind: "cash")).to be_empty
      expect(balance(:cocoscout_balance)).to eq(2_000)
      books_balance_rows
    end
  end

  describe "the payout ledger" do
    let(:payee) { create(:person) }

    it "posts earnings as pay owed, a payout through a run once, and a bank return" do
      production = create(:production, organization: org)
      show = create(:show, production: production)
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: 15_000,
                              source: show, description: "Show pay", category: "performer")
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: 4_000,
                              source: create(:show, production: production), description: "Shift", category: "staffing")
      expect(balance(:performer_pay)).to eq(15_000)
      expect(balance(:staff_pay)).to eq(4_000)
      expect(balance(:owed_to_payees)).to eq(19_000)
      expect(JournalLine.where(organization: org, show: show).count).to eq(1)
      books_balance_rows

      # Paid on a run: the cash row carries the money; the payout row posts nothing twice.
      batch = PayoutBatch.create!(organization: org, status: "funded")
      OrgCashEntry.post!(organization: org, entry_type: "funding", amount_cents: 19_000, source: batch)
      item = batch.items.create!(payee: payee, amount_cents: 19_000, status: "pending")
      OrgCashEntry.post!(organization: org, entry_type: "transfer", amount_cents: -19_000, source: item)
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "payout", amount_cents: -19_000, source: item, category: "performer")
      expect(balance(:owed_to_payees)).to eq(0)
      expect(JournalEntry.live.where(organization: org, source: item.payout_ledger_entries.first)).to be_empty
      books_balance_rows

      # The bank sends it back: owed again, parked with the payee, then back in the balance.
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "reversal", amount_cents: 19_000, source: item, category: "performer")
      expect(balance(:owed_to_payees)).to eq(19_000)
      expect(balance(:owed_to_you)).to eq(19_000)
      OrgCashEntry.post!(organization: org, entry_type: "transfer_reversal", amount_cents: 19_000, source: item)
      expect(balance(:owed_to_you)).to eq(0)
      expect(balance(:cocoscout_balance)).to eq(19_000)
      books_balance_rows
    end

    it "posts a payout paid another way out of the bank, and a contract deduction as contract income" do
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: 8_000, description: "Show pay")
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "payout", amount_cents: -8_000, description: "Paid via check")
      expect(balance(:bank)).to eq(-8_000)
      expect(balance(:owed_to_payees)).to eq(0)

      contract = create(:contract, organization: org, status: "active")
      payment = contract.contract_payments.create!(amount: 300, direction: "incoming", description: "Tech", due_date: Date.current)
      batch = PayoutBatch.create!(organization: org, status: "draft")
      item = batch.items.create!(payee: payee, amount_cents: 1, status: "pending")
      contribution = PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: payee,
                                                source: payment, amount_cents: -30_000, label: "Tech (deducted)")
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "adjustment", amount_cents: -30_000, source: contribution)
      expect(balance(:contract_income)).to eq(30_000)
      books_balance_rows
    end
  end
end
