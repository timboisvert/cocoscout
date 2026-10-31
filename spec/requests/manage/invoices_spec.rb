# frozen_string_literal: true

require "rails_helper"

# Invoices to anyone (Books V1.3, plan D2): made from Incoming Payments,
# numbered in the organization's one sequence, sent by email with a page
# where they pay by card, or recorded by hand when the check comes.
RSpec.describe "Manage::Invoices", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Holiday Revue") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def make_invoice(send_now: nil)
    post manage_money_invoices_path, params: { send_now: send_now, invoice: {
      bill_to_name: "Acme Bank", bill_to_email: "ap@acme.test", bill_to_attention: "Accounts payable", due_on: (Date.current + 15).iso8601,
      category_key: "sponsorship", production_id: production.id, memo: "Thank you for sponsoring the season.", pay_by_card: "1", pay_by_bank: "1", pay_by_check: "1", reminders: "before_and_overdue",
      invoice_lines_attributes: { "0" => { description: "Season sponsorship", quantity: "1", unit: "1500.00" }, "1" => { description: "Program ad", quantity: "2", unit: "125.00" } }
    }.compact }
    org.invoices.last
  end

  it "makes an invoice from the form, numbered, and puts it on the books as money owed to you" do
    get manage_money_incoming_path
    expect(response.body).to include(manage_new_money_invoice_path)
    get manage_new_money_invoice_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Send an invoice", "Who it is to", "Add a line", "By card online")

    invoice = make_invoice
    expect(response).to redirect_to(manage_money_invoice_path(invoice))
    expect(invoice.total_cents).to eq(175_000)
    expect(invoice.display_number).to match(/\A[A-Z0-9]+-\d{4}\z/)
    expect(invoice.sent_at).to be_nil
    expect(ChartOfAccounts.account(org, :owed_to_you).natural_balance_cents).to eq(175_000)
    expect(ChartOfAccounts.account(org, :sponsorship_income).natural_balance_cents).to eq(175_000)
    expect(invoice.journal_entry.cash_date).to be_nil

    get manage_money_invoice_path(invoice)
    expect(response.body).to include("Acme Bank", "Season sponsorship", "Program ad", "$1,750.00", "Record a payment", "Send", "Money owed to you", pay_invoice_path(token: invoice.reload.payment_token))

    get manage_money_incoming_path
    expect(response.body).to include("Invoices", "Acme Bank", invoice.display_number)
    get manage_money_index_path
    expect(response.body).to include("Acme Bank", "Owed to you")
  end

  it "sends it by email with the PDF, from the organization's template" do
    invoice = nil
    expect { invoice = make_invoice(send_now: "1") }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    expect(invoice.reload.sent_count).to eq(1)
    expect(invoice.sent_at).to be_present

    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "ap@acme.test" ])
    expect(mail.subject).to include(invoice.display_number, "Stars and Garters", "$1,750.00")
    expect(mail.attachments.map(&:filename)).to include(invoice.filename)
    expect(mail.html_part.body.to_s).to include(pay_invoice_path(token: invoice.payment_token!), "Thank you for sponsoring the season.")

    post manage_send_money_invoice_path(invoice)
    expect(invoice.reload.sent_count).to eq(2)
    expect(flash[:notice]).to include("Reminder")
  end

  it "records a check by hand, moves the money into the bank, and emails the receipt once paid in full" do
    invoice = make_invoice
    post manage_payments_money_invoice_path(invoice), params: { on: Date.current.iso8601, amount: "1000.00", via: "check", reference: "2210" }
    expect(invoice.reload).to be_open
    expect(invoice.unpaid_cents).to eq(75_000)
    expect(ChartOfAccounts.account(org, :owed_to_you).natural_balance_cents).to eq(75_000)
    expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(100_000)
    expect(ChartOfAccounts.account(org, :sponsorship_income).natural_balance_cents).to eq(175_000)

    expect { post manage_payments_money_invoice_path(invoice), params: { on: Date.current.iso8601, amount: "", via: "bank_transfer" } }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    expect(invoice.reload).to be_paid
    expect(invoice.receipt_emailed_at).to be_present
    expect(ChartOfAccounts.account(org, :owed_to_you).natural_balance_cents).to eq(0)
    expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(175_000)
    expect(BooksReconciliation.check(org)).to be_empty

    get manage_money_invoice_path(invoice)
    expect(response.body).to include("Paid", "Check · 2210", "Bank transfer")
  end

  it "has a public page where they can see it, download it, and pay" do
    invoice = make_invoice
    get signout_path

    get pay_invoice_path(token: invoice.payment_token!)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Invoice from Stars and Garters", "Season sponsorship", "Pay $1,750.00", "Download invoice (PDF)")

    get pay_invoice_pdf_path(token: invoice.payment_token, format: :pdf)
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include("application/pdf")

    get pay_invoice_path(token: "nope")
    expect(response).to have_http_status(:not_found)
  end

  it "settles a paid checkout session into the CocoScout balance, less the fee" do
    invoice = make_invoice
    session = double("session", id: "cs_test_inv", payment_intent: nil, amount_total: 175_000)
    expect(InvoiceCollection.settle!(invoice, session)).to be(true)
    expect(invoice.reload).to be_paid
    expect(invoice.invoice_payments.last.via).to eq("online")
    expect(OrgCashEntry.where(organization: org, entry_type: "invoice_payment").sum(:amount_cents)).to eq(175_000)
    expect(ChartOfAccounts.account(org, :owed_to_you).natural_balance_cents).to eq(0)
    expect(ChartOfAccounts.account(org, :cocoscout_balance).natural_balance_cents).to eq(175_000)
    expect(BooksReconciliation.check(org)).to be_empty
    # The same session twice is one payment.
    expect(InvoiceCollection.settle!(invoice, session)).to be(false)
  end

  it "cancels an invoice off the books, keeping its number" do
    invoice = make_invoice
    post manage_void_money_invoice_path(invoice), params: { reason: "Wrong amount" }
    expect(response).to redirect_to(manage_money_incoming_path)
    expect(invoice.reload).to be_void
    expect(ChartOfAccounts.account(org, :owed_to_you).natural_balance_cents).to eq(0)
    expect(org.reload.invoice_next_number).to eq(invoice.number + 1)
    get pay_invoice_path(token: invoice.payment_token!)
    expect(response.body).to include("cancelled")
  end
end
