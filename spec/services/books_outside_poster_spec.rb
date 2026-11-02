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
    expect(balance(:venue)).to eq(30_000)
    expect(balance(:marketing)).to eq(2_525)
    # Outside money arrives in the bank; the expenses left it.
    expect(balance(:bank)).to eq(95_050 - 32_525)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    expect(JournalEntry.live.where(organization: org, source: financials).pluck(:kind)).to contain_exactly("outside_tickets", "other_revenue", "expenses")

    financials.ticket_sales_lines.first.update!(amount: 500)
    financials.expense_items.destroy_all
    expect(balance(:ticket_income)).to eq(50_000)
    expect(balance(:venue)).to eq(0)
    expect(balance(:bank)).to eq(65_050)

    financials.destroy
    expect(balance(:ticket_income)).to eq(0)
    expect(balance(:bank)).to eq(0)
  end

  # Who pays the tax on tickets another site sold (Tim, 10/31): a source the
  # organization owes the tax for carves it out of what arrived, at the
  # ticket tax rate, into Tax to pay the government; a source that pays its
  # own tax (Eventbrite in Chicago) posts the whole amount as income.
  it "sets the tax part of a 'we owe the tax' source's sales aside as owed to the government" do
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    tailor.update!(tax_handling: "we_owe")
    eventbrite = org.ticket_sources.create!(name: "Eventbrite", tax_handling: "they_pay")
    financials = ShowFinancials.create!(show: show, revenue_type: "ticket_sales")
    financials.ticket_sales_lines.create!(ticket_source: tailor, tickets_sold: 10, amount: 220.50)
    financials.ticket_sales_lines.create!(ticket_source: eventbrite, tickets_sold: 5, amount: 110.25)
    financials.reload

    # 22050 × 1025 / 11025 = 2050 cents of tax inside Ticket Tailor's money.
    expect(OutsideTicketTax.tax_cents(org, 22_050)).to eq(2_050)
    expect(balance(:bank)).to eq(33_075)
    expect(balance(:tax_to_remit)).to eq(2_050)
    expect(balance(:ticket_income)).to eq(33_075 - 2_050)
    expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)

    rows = OutsideTicketTax.rows(org, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31))
    expect(rows.map { |r| [ r.source.name, r.sales_cents, r.tax_cents, r.shows ] }).to eq([ [ "Ticket Tailor", 22_050, 2_050, 1 ] ])
    expect(BooksReconciliation.check(org)).to eq([])

    # Switching the source to "they pay" restates: no tax owed any more.
    tailor.update!(tax_handling: "they_pay")
    financials.reload.post_to_books
    expect(balance(:tax_to_remit)).to eq(0)
    expect(balance(:ticket_income)).to eq(33_075)
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
    expect(balance(:bank)).to eq(64_000)

    line = financials.ticket_sales_lines.create!(ticket_source: tailor, tickets_sold: 10, amount: 200)
    expect(balance(:ticket_income)).to eq(20_000)
    line.destroy!
    expect(financials.reload.ticket_revenue).to eq(0)
    expect(balance(:ticket_income)).to eq(0)
  end

  it "posts a flat fee only when no contract carries it" do
    financials = ShowFinancials.create!(show: show, revenue_type: "flat_fee", flat_fee: 120, ticket_revenue: 999)
    expect(balance(:contract_income)).to eq(12_000)
    expect(balance(:bank)).to eq(12_000)
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

    # Earned on the date it's for (its due date), moved the day it was paid
    # (Tim, 2026-11-02): an October rehearsal paid in November is October's.
    it "posts a check received: earned on the date it's for, moved on the day it was paid; taken back when unpaid again" do
      rent = payment("incoming", 350)
      expect(balance(:contract_income)).to eq(0)

      rent.mark_paid!(paid_on: Date.new(2026, 11, 3), method: "check")
      expect(balance(:contract_income)).to eq(35_000)
      expect(balance(:bank)).to eq(35_000)
      entry = JournalEntry.live.find_by(source: rent)
      expect([ entry.entry_date, entry.cash_date ]).to eq([ Date.new(2026, 10, 1), Date.new(2026, 11, 3) ])

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

    it "moves money already on the books to the date it's for, reversing on the old entry's own dates" do
      rent = payment("incoming", 350)
      rent.mark_paid!(paid_on: Date.new(2026, 11, 3), method: "check")
      old = JournalEntry.live.find_by(source: rent)
      old.update_columns(entry_date: Date.new(2026, 11, 3)) # as the books used to date it

      expect(ContractMoneyRedate.run!).to eq(1)
      expect(JournalEntry.live.find_by(source: rent).entry_date).to eq(Date.new(2026, 10, 1))
      reversal = JournalEntry.find_by(reversal_of_id: old.id)
      expect([ reversal.entry_date, reversal.cash_date ]).to eq([ Date.new(2026, 11, 3), Date.new(2026, 11, 3) ])
      income_in = ->(month) { -JournalLine.joins(:journal_entry).where(ledger_account: ChartOfAccounts.account(org, :contract_income), journal_entries: { entry_date: month.all_month }).sum(:amount_cents) }
      expect([ income_in.call(Date.new(2026, 10, 1)), income_in.call(Date.new(2026, 11, 1)) ]).to eq([ 35_000, 0 ])
      expect(balance(:contract_income)).to eq(35_000)

      expect(ContractMoneyRedate.run!).to eq(0)
    end

    it "leaves money in a closed month where it is when only its date would change" do
      rent = payment("incoming", 350)
      rent.mark_paid!(paid_on: Date.new(2026, 10, 3), method: "check")
      old = JournalEntry.live.find_by(source: rent)
      old.update_columns(entry_date: Date.new(2026, 10, 3)) # as the books used to date it
      org.update!(books_locked_through: Date.new(2026, 10, 31))

      expect(ContractMoneyRedate.run!).to eq(0)
      expect(JournalEntry.live.find_by(source: rent)).to eq(old)
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

  it "reads old category keys as the category they meant, and an organization's own category as its account" do
    financials = ShowFinancials.create!(show: show, revenue_type: "ticket_sales")
    financials.expense_items.create!(category: "talent", amount: 100)
    financials.expense_items.create!(category: "tech", amount: 50)
    own = org.ledger_accounts.create!(name: "Costume shop", account_type: "expense", code: "5800", system: false, active: true)
    financials.expense_items.create!(category: "account_#{own.id}", amount: 20)
    financials.reload
    expect(balance(:performer_pay)).to eq(10_000)
    expect(balance(:equipment)).to eq(5_000)
    expect(own.natural_balance_cents).to eq(2_000)
    expect(MoneyCategories.label_for("talent")).to eq("Performer pay")
    expect(MoneyCategories.label_for("account_#{own.id}", organization: org)).to eq("Costume shop")
    expect(MoneyCategories.spending_options(org).map(&:first)).to include("Costume shop")
    expect(MoneyCategories.spending_options(org).last.last).to eq("other")
  end

  it "puts a paid CocoScout bill on the books as software spending" do
    bill = BillingInvoice.create!(organization: org, stripe_invoice_id: "in_1", status: "open", kind: "pro", amount_due_cents: 2_000)
    expect(balance(:software)).to eq(0)
    bill.update!(status: "paid", amount_paid_cents: 2_000, paid_at: Time.current)
    expect(balance(:software)).to eq(2_000)
    expect(balance(:bank)).to eq(-2_000)
    expect(JournalEntry.live.find_by(organization: org, source: bill, kind: "cocoscout_bill").memo).to include("CocoScout")
  end
end
