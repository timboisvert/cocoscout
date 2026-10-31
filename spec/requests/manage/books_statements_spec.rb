# frozen_string_literal: true

require "rails_helper"

# Books → Statements (V1.3, plan E1 and E2): profit and loss, the balance
# sheet and cash flow from the ledger; the closed-months lock.
RSpec.describe "Manage::BooksStatements", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Holiday Revue") }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    org.money_records.create!(kind: "in", on: Date.current.beginning_of_month, amount_cents: 90_000, category_key: "sponsorship", counterparty: "Chamber", via: "bank", production: production, recorded_by: owner)
    org.money_records.create!(kind: "out", on: Date.current.beginning_of_month + 1, amount_cents: 24_000, category_key: "production", counterparty: "Lumber", via: "card", recorded_by: owner)
  end

  it "shows profit and loss for the month, by production too, and offers print, PDF and CSV" do
    get manage_money_statements_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Profit and loss", "Sponsorship", "$900.00", "Production", "$240.00", "Profit", "$660.00", "Lock the books", "The whole ledger (CSV)")

    get manage_money_statements_path(by_production: "1")
    expect(response.body).to include("Holiday Revue", "Not tied to a production")

    get manage_money_statements_path(print: "1")
    expect(response.body).to include(org.name, "Profit and loss")
    expect(response.body).not_to include("Lock the books")

    get manage_money_statements_path(format: :pdf)
    expect(response.content_type).to include("application/pdf")

    get manage_money_statements_path(format: :csv)
    expect(response.body).to include("Profit and loss", "Sponsorship,900.00", "Profit,660.00")

    get manage_money_statements_ledger_path
    expect(response.body).to include("Entry,Earned on,Moved on", "Sponsorship", "900.00")
  end

  it "shows the balance sheet, which agrees with itself, and cash flow" do
    get manage_money_statements_path(kind: "balance")
    expect(response.body).to include("Balance sheet", "What you have", "Bank", "$900.00", "Credit card", "$240.00", "Earnings kept in the organization to date", "$660.00", "What you owe plus owner")
    statement = BooksStatements.new(org).balance_sheet(Date.current)
    expect(statement.sections.first.total_cents).to eq(statement.bottom.cents)

    get manage_money_statements_path(kind: "cash")
    expect(response.body).to include("Cash flow", "Came in", "Recorded by hand", "$900.00", "Cash at the end", "Change in cash")
  end

  it "uses nonprofit words when the organization says so" do
    patch manage_money_settings_books_path, params: { books_nonprofit: "1" }
    expect(org.reload.books_nonprofit).to be(true)
    get manage_money_statements_path
    expect(response.body).to include("Statement of activities", "Support and revenue", "Change in net assets")
    get manage_money_statements_path(kind: "balance")
    expect(response.body).to include("Statement of financial position", "Net assets")
  end

  it "locks the books through a month: forms refuse dates inside it, the engine posts restatements on the first open day, the owner unlocks" do
    last_month = Date.current.prev_month.end_of_month
    post manage_money_statements_lock_path, params: { through: last_month.beginning_of_month.iso8601 }
    expect(response).to redirect_to(manage_money_statements_path)
    expect(org.reload.books_locked_through).to eq(last_month)
    expect(org.books_locked_by).to eq(owner)

    get manage_money_statements_path
    expect(response.body).to include("locked through", last_month.strftime("%B %-d, %Y"), "Unlock")

    # A hand record dated inside the lock is refused with the reason.
    record = org.money_records.new(kind: "out", on: last_month - 3, amount_cents: 1_000, category_key: "supplies", counterparty: "X", via: "bank")
    expect(record).not_to be_valid
    expect(record.errors[:on].first).to include("closed month", "locked through")
    bill = org.bills.new(vendor_name: "Late", amount_cents: 500, issued_on: last_month, due_on: Date.current, category_key: "venue")
    expect(bill).not_to be_valid

    # Something the engine restates inside the lock lands on the first open day.
    old = org.money_records.create!(kind: "out", on: Date.current, amount_cents: 1_000, category_key: "supplies", counterparty: "Y", via: "bank")
    LedgerPosting.post!(organization: org, source: old, kind: "recorded", entry_date: last_month - 5, cash_date: last_month - 5, memo: "restated",
                        lines: [ { account: :supplies, amount_cents: 1_000 }, { account: :bank, amount_cents: -1_000 } ])
    entry = JournalEntry.live.find_by(source_type: "MoneyRecord", source_id: old.id, kind: "recorded")
    expect(entry.entry_date).to eq(last_month + 1)
    expect(entry.memo).to include("books closed through")

    # A manager who is not the owner cannot unlock.
    manager = create(:user, password: password)
    create(:organization_role, :manager, user: manager, organization: org)
    get signout_path
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    post manage_money_statements_unlock_path
    expect(org.reload.books_locked_through).to eq(last_month)

    get signout_path
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    post manage_money_statements_unlock_path
    expect(org.reload.books_locked_through).to be_nil
  end
end
