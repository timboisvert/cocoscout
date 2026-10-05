# frozen_string_literal: true

require "rails_helper"

# Books stage B, the money that never passes through CocoScout: a show's
# sales elsewhere, its other revenue and its expenses, and a production's
# spread expenses, posted from the records they're typed into and restated
# when those change. Plus the backfill that posts history, and the checks.
RSpec.describe BooksOutsidePoster do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs") }
  let(:show) { create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 10, 19, 30)) }
  let(:tailor) { org.ticket_sources.create!(name: "Ticket Tailor") }

  def balance(key)
    ChartOfAccounts.account(org, key).natural_balance_cents
  end

  it "posts a show's outside ticket sales, other revenue and expenses, and restates them as the worksheet changes" do
    financials = ShowFinancials.create!(show: show, revenue_type: "ticket_sales")
    financials.ticket_sales_lines.create!(ticket_source: tailor, tickets_sold: 40, amount: 800.00)
    financials.update!(other_revenue_details: [ { "description" => "Bar", "amount" => 150.5 }, { "description" => TicketSalesSync::PRODUCTS_LABEL, "amount" => 90 } ])
    financials.expense_items.create!(category: "venue", amount: 300, description: "Room")
    financials.expense_items.create!(category: "marketing", amount: 25.25)
    financials.reload

    expect(balance(:ticket_income)).to eq(80_000)
    expect(balance(:other_income)).to eq(15_050)
    expect(balance(:owed_to_you)).to eq(95_050)
    expect(balance(:venue)).to eq(30_000)
    expect(balance(:marketing)).to eq(2_525)
    expect(balance(:bank)).to eq(-32_525)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    expect(JournalEntry.live.where(organization: org, source: financials).pluck(:kind)).to contain_exactly("outside_tickets", "other_revenue", "expenses")

    financials.ticket_sales_lines.first.update!(amount: 500)
    financials.expense_items.destroy_all
    expect(balance(:ticket_income)).to eq(50_000)
    expect(balance(:venue)).to eq(0)
    expect(balance(:bank)).to eq(0)

    financials.destroy
    expect(balance(:ticket_income)).to eq(0)
    expect(balance(:owed_to_you)).to eq(0)
  end

  it "leaves another seller's ticket money out, and the CocoScout row too" do
    contract = create(:contract, organization: org, production: production)
    allow_any_instance_of(Contract).to receive(:org_sells_tickets?).and_return(false)
    financials = ShowFinancials.create!(show: show, revenue_type: "ticket_sales")
    financials.ticket_sales_lines.create!(ticket_source: tailor, tickets_sold: 10, amount: 200)
    expect(balance(:ticket_income)).to eq(0)

    allow_any_instance_of(Contract).to receive(:org_sells_tickets?).and_return(true)
    cocoscout = TicketSource.find_or_create_by!(organization: org, system_key: "cocoscout") { |s| s.name = "CocoScout Tickets" }
    financials.ticket_sales_lines.create!(ticket_source: cocoscout, tickets_sold: 5, amount: 100)
    financials.ticket_sales_lines.first.update!(amount: 250)
    expect(balance(:ticket_income)).to eq(25_000)
    expect(contract).to be_present
  end

  it "posts ticket revenue typed before sources existed, and stops counting a line once it's deleted" do
    financials = ShowFinancials.create!(show: show, revenue_type: "ticket_sales", ticket_revenue: 640, ticket_count: 32)
    expect(balance(:ticket_income)).to eq(64_000)
    expect(balance(:owed_to_you)).to eq(64_000)

    line = financials.ticket_sales_lines.create!(ticket_source: tailor, tickets_sold: 10, amount: 200)
    expect(balance(:ticket_income)).to eq(20_000)
    line.destroy!
    expect(financials.reload.ticket_revenue).to eq(0)
    expect(balance(:ticket_income)).to eq(0)
  end

  it "posts a flat fee only when no contract carries it" do
    financials = ShowFinancials.create!(show: show, revenue_type: "flat_fee", flat_fee: 120, ticket_revenue: 999)
    expect(balance(:contract_income)).to eq(12_000)
    expect(balance(:owed_to_you)).to eq(12_000)
    expect(balance(:ticket_income)).to eq(0)

    create(:contract, organization: org, production: production)
    financials.update!(flat_fee: 150)
    expect(balance(:contract_income)).to eq(0)
  end

  describe "contract money that moved outside CocoScout" do
    let(:contract) { create(:contract, organization: org, production: production) }

    def payment(direction, amount, **attrs)
      contract.contract_payments.create!(direction: direction, amount: amount, due_date: Date.new(2026, 10, 1), description: "Rent", **attrs)
    end

    it "posts a check received on the day it was paid, and takes it back when it's unpaid again" do
      rent = payment("incoming", 350)
      expect(balance(:contract_income)).to eq(0)

      rent.mark_paid!(paid_on: Date.new(2026, 10, 3), method: "check")
      expect(balance(:contract_income)).to eq(35_000)
      expect(balance(:bank)).to eq(35_000)
      expect(JournalEntry.live.find_by(source: rent).entry_date).to eq(Date.new(2026, 10, 3))

      rent.update!(status: :pending, paid_date: nil)
      expect(balance(:contract_income)).to eq(0)
      expect(balance(:bank)).to eq(0)
    end

    it "posts a contractor paid by hand, with the services netted out of it" do
      share = payment("outgoing", 500)
      tech = payment("incoming", 50, settlement_method: "payout_deduction")
      share.pay_offline!(method: "check", deductions: [ tech ])

      expect(balance(:contractor_pay)).to eq(50_000)
      expect(balance(:contract_income)).to eq(5_000)
      expect(balance(:bank)).to eq(-45_000)
      expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    end

    it "leaves money already on a ledger alone: collected online, or riding a payout run" do
      online = payment("incoming", 200)
      online.mark_paid_online!(checkout_session_id: "cs_test_1", payment_intent_id: "pi_test_1")
      run_share = payment("outgoing", 300)
      batch = PayoutBatch.open_for(org)
      payee = create(:person)
      item = batch.items.create!(payee: payee, amount_cents: 30_000, status: "pending")
      PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: payee, source: run_share, amount_cents: 30_000, label: "Share")
      run_share.mark_paid_via_payout_run!(reference_id: "tr_1")

      expect(JournalEntry.live.where(source_type: "ContractPayment")).to be_empty
    end

    it "is picked up by the backfill" do
      rent = payment("incoming", 350)
      rent.update_columns(status: "paid", paid_date: Date.new(2026, 10, 3), payment_method: "cash")
      row = BooksBackfill.run!(dry_run: false, organization_ids: [ org.id ]).rows.sole
      expect(row.contract_payments).to eq(1)
      expect(balance(:contract_income)).to eq(35_000)
      BooksBackfill.run!(dry_run: false, organization_ids: [ org.id ])
      expect(balance(:contract_income)).to eq(35_000)
    end
  end

  it "posts a production's spread expense once, on its date, and takes it off when it's inactive" do
    expense = production.production_expenses.create!(name: "Costumes", category: "production", total_amount: 420.00, purchase_date: Date.new(2026, 9, 1), spread_method: "fixed_months", spread_months: 3)
    expect(balance(:production_costs)).to eq(42_000)
    expect(balance(:bank)).to eq(-42_000)
    expect(JournalEntry.find_by(source: expense).entry_date).to eq(Date.new(2026, 9, 1))

    expense.update!(active: false)
    expect(balance(:production_costs)).to eq(0)
  end

  describe "the backfill and the checks" do
    it "posts history again without doubling anything, dry run first, and the checks agree" do
      financials = ShowFinancials.create!(show: show, revenue_type: "ticket_sales")
      financials.ticket_sales_lines.create!(ticket_source: tailor, tickets_sold: 4, amount: 80)
      OrgCashEntry.post!(organization: org, entry_type: "opening_balance", amount_cents: 5_000, source: org, description: "Opening", occurred_at: Time.current)
      result = BooksBackfill.run!(dry_run: true, organization_ids: [ org.id ])
      row = result.rows.sole
      expect(row.cash_rows).to eq(1)
      expect(row.financials).to eq(1)
      expect(row.mismatches).to eq([])
      expect(row.trial_balance_cents).to eq(0)

      JournalLine.where(journal_entry_id: JournalEntry.where(organization: org).select(:id)).delete_all
      JournalEntry.where(organization: org).delete_all
      expect(BooksReconciliation.check(org).map(&:account)).to include("cocoscout_balance")

      BooksBackfill.run!(dry_run: false, organization_ids: [ org.id ])
      expect(BooksReconciliation.check(org)).to eq([])
      expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
      expect(balance(:cocoscout_balance)).to eq(5_000)
      expect(balance(:ticket_income)).to eq(8_000)
    end
  end
end
