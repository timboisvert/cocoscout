# frozen_string_literal: true

require "rails_helper"

# Bills (Books V1.3, plan D1): what the organization owes and has not paid.
# A bill goes on the books the day it arrives as Money you owe, and again
# the day it is paid, from wherever it was paid.
RSpec.describe "Manage::Bills", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Holiday Revue") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "adds a bill and puts the unpaid amount on the books as money you owe" do
    get manage_new_money_bill_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add a bill", "Who you owe", "Holiday Revue")

    post manage_money_bills_path, params: { bill: { vendor_name: "Chicago Lumber Co.", amount: "1,240.00", issued_on: "2026-10-20", due_on: "2026-11-19",
                                                    category_key: "production", production_id: production.id, memo: "Set lumber", repeats: "none" } }
    bill = org.bills.last
    expect(response).to redirect_to(manage_money_bill_path(bill))
    expect(bill.amount_cents).to eq(124_000)
    expect(ChartOfAccounts.account(org, :you_owe).natural_balance_cents).to eq(124_000)
    expect(bill.journal_entry.cash_date).to be_nil
    expect(BooksReconciliation.check(org)).to be_empty

    get manage_money_bill_path(bill)
    expect(response.body).to include("Chicago Lumber Co.", "$1,240.00", "Set lumber", "Mark paid", "Money you owe")

    get manage_money_bills_path
    expect(response.body).to include("Later", "Chicago Lumber Co.", "Owed in all")
  end

  it "marks a bill paid, in part and then in full, and the next of a repeating one appears" do
    bill = org.bills.create!(vendor_name: "Rent", amount_cents: 200_000, issued_on: Date.current - 3, due_on: Date.current + 4, category_key: "venue", repeats: "monthly", created_by: owner)

    post manage_pay_money_bill_path(bill), params: { on: Date.current.iso8601, amount: "500.00", via: "card", reference: "Visa 4411" }
    expect(response).to redirect_to(manage_money_bill_path(bill))
    expect(bill.reload).to be_open
    expect(bill.paid_cents).to eq(50_000)
    expect(ChartOfAccounts.account(org, :you_owe).natural_balance_cents).to eq(150_000)
    expect(ChartOfAccounts.account(org, :credit_card).natural_balance_cents).to eq(50_000)
    expect(ChartOfAccounts.account(org, :venue).natural_balance_cents).to eq(200_000)

    post manage_pay_money_bill_path(bill), params: { on: Date.current.iso8601, amount: "", via: "bank" }
    expect(bill.reload).to be_paid
    expect(ChartOfAccounts.account(org, :you_owe).natural_balance_cents).to eq(200_000 - 200_000 + org.bills.open.sum(:amount_cents))
    following = org.bills.open.find_by(repeated_from: bill)
    expect(following).to be_present
    expect(following.due_on).to eq(bill.due_on >> 1)
    expect(following.amount_cents).to eq(200_000)
    expect(BooksReconciliation.check(org)).to be_empty

    get manage_money_bills_path
    expect(response.body).to include("Repeats", "Monthly, next")
  end

  it "lists overdue bills on the Money hub and cancels one off the books" do
    late = org.bills.create!(vendor_name: "Insurance Co.", amount_cents: 80_000, issued_on: Date.current - 40, due_on: Date.current - 10, category_key: "insurance")

    get manage_money_index_path
    expect(response.body).to include("$800.00 in bills past due", "Bills due", "Insurance Co.", manage_money_bills_path)

    post manage_void_money_bill_path(late), params: { reason: "Paid from the other account" }
    expect(response).to redirect_to(manage_money_bills_path)
    expect(late.reload).to be_void
    expect(ChartOfAccounts.account(org, :you_owe).natural_balance_cents).to eq(0)
    get manage_money_bill_path(late)
    expect(response.body).to include("Cancelled", "Paid from the other account")
  end

  it "lets a view-only manager look but not change" do
    viewer = create(:user, password: password)
    create(:organization_role, user: viewer, organization: org, company_role: "viewer", module_grants: { "bills_invoices" => "view", "books" => "view" })
    get signout_path
    post handle_signin_path, params: { email_address: viewer.email_address, password: password }

    get manage_money_bills_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(manage_new_money_bill_path)
    get manage_new_money_bill_path
    expect(response).to redirect_to(manage_money_bills_path)
  end
end
