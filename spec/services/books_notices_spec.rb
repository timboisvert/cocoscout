# frozen_string_literal: true

require "rails_helper"

# The Books notices added on 2026-11-09 (Tim: "Yes, all of it"): an invoice
# paid on its page, and background work that didn't finish. Each is a
# notification (the list and a push), never an email, and a notice that
# can't be sent never fails the work it is about.
RSpec.describe BooksNotices do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  describe "an invoice paid on its page" do
    let(:invoice) do
      org.invoices.create!(bill_to_name: "Acme Bank", bill_to_email: "ap@acme.test", issued_on: Date.current, due_on: Date.current + 15, category_key: "sponsorship",
                           created_by: owner, invoice_lines_attributes: [ { description: "Season sponsorship", quantity: "1", unit: "1750.00" } ])
    end
    let(:session) { double("session", id: "cs_test_inv", payment_intent: nil, amount_total: 175_000) }

    it "tells whoever made the invoice, once, and sends them no email" do
      expect { InvoiceCollection.settle!(invoice, session) }.to change { owner.notifications.where(kind: "invoice_paid").count }.by(1)
      notice = owner.notifications.last
      expect(notice.title).to eq("Acme Bank paid $1,750.00 on invoice #{invoice.display_number}")
      expect(notice.path).to eq(Rails.application.routes.url_helpers.manage_money_invoice_path(invoice))
      expect(notice.category).to eq("books")
      perform_enqueued_jobs
      # The only email is their receipt.
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ "ap@acme.test" ] ])
      # The same session coming back (the page and the webhook both report it) says nothing more.
      expect { InvoiceCollection.settle!(invoice, session) }.not_to(change { owner.notifications.count })
    end

    it "says what is still owed when the payment didn't cover it" do
      part = double("session", id: "cs_test_part", payment_intent: nil, amount_total: 100_000)
      InvoiceCollection.settle!(invoice, part)
      body = ContentTemplateService.render_body("invoice_paid_online", { "still_owed" => "$750.00", "payer_name" => "Acme Bank", "amount" => "$1,000.00" })
      expect(owner.notifications.last.title).to include("Acme Bank paid $1,000.00")
      expect(body.to_s).to include("$750.00 is still owed on it")
      expect(ContentTemplateService.render_body("invoice_paid_online", { "still_owed" => "" }).to_s).not_to include("still owed")
    end

    it "tells the owner when whoever made it can no longer see invoices, and nobody about a check recorded by hand" do
      gone = create(:user)
      invoice.update_columns(created_by_id: gone.id)
      invoice.receive!(on: Date.current, amount_cents: 50_000, via: "check", by: owner)
      expect(owner.notifications.count).to eq(0)

      expect { InvoiceCollection.settle!(invoice, session) }.to change { owner.notifications.where(kind: "invoice_paid").count }.by(1)
      expect(gone.notifications.count).to eq(0)
    end

    it "still takes the money when the notice can't be sent" do
      allow(Notifier).to receive(:deliver).and_raise(StandardError, "push is down")
      expect(InvoiceCollection.settle!(invoice, session)).to be(true)
      expect(invoice.reload).to be_paid
    end
  end

  describe "a statement whose matching didn't finish" do
    let(:import) { org.bank_statement_imports.create!(imported_by: owner, filename: "october.csv", format: "csv", lines_count: 0, status: "matching") }

    it "says so to whoever brought it in, and leaves the statement marked as not finished" do
      allow(BankStatementMatcher).to receive(:run!).and_raise(StandardError, "boom")
      expect { BankStatementMatchJob.perform_now(import.id) }.to raise_error(StandardError, "boom")
      expect(import.reload.status).to eq("failed")
      notice = owner.notifications.find_by(kind: "bank_statement_failed")
      expect(notice.title).to eq("The matching for #{import.title} didn't finish")
      expect(notice.path).to eq("/manage/money/books/bank")
      expect(owner.notifications.where(kind: "bank_statement_ready")).to be_empty
    end

    it "keeps a statement that matched as matched when its own notice can't be sent" do
      allow(Notifier).to receive(:deliver).and_raise(StandardError, "push is down")
      expect { BankStatementMatchJob.perform_now(import.id) }.to raise_error(StandardError, "push is down")
      expect(import.reload.status).to eq("ready")
    end
  end

  describe "a run of bank rules that stopped part way" do
    it "says how many lines are still waiting" do
      import = org.bank_statement_imports.create!(imported_by: owner, filename: "october.csv", format: "csv", lines_count: 2, status: "ready")
      2.times { |i| import.bank_statement_lines.create!(organization: org, on: Date.new(2026, 10, 5 + i), amount_cents: -1_200, description: "COFFEE #{i}") }
      allow(BankRules).to receive(:apply!).and_raise(StandardError, "boom")
      expect { BankRulesApplyJob.perform_now(org.id, owner.id) }.to raise_error(StandardError, "boom")
      notice = owner.notifications.find_by(kind: "bank_rules_failed")
      expect(notice.title).to eq("Your bank rules stopped part way: 2 lines still waiting")
      expect(notice.path).to eq("/manage/money/books/bank/rules")
    end
  end

  describe "a download that couldn't be made" do
    it "says so to whoever asked, since they were promised a notification" do
      download = org.books_downloads.create!(requested_by: owner, kind: "ledger", options: {})
      allow_any_instance_of(BooksDownload).to receive(:write).and_raise(StandardError, "disk full")
      expect { BooksDownloadJob.perform_now(download.id) }.to raise_error(StandardError, "disk full")
      expect(download.reload).to be_failed
      notice = owner.notifications.find_by(kind: "books_download_failed")
      expect(notice.title).to eq("#{download.title} couldn't be put together")
      expect(notice.path).to eq("/manage/money/books/statements")
    end
  end
end
