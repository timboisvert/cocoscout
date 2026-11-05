# frozen_string_literal: true

require "rails_helper"

# Superadmin Finances, Costs: what CocoScout costs to run outside Stripe
# (Amazon, Claude). Bills are uploaded, read, checked, and only then count
# in Spent and Profit beside CocoScout's Stripe ledger.
RSpec.describe "Superadmin Finances - Costs", type: :request do
  let(:superadmin_user) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }
  let(:regular_user) { create(:user, password: "Password123!") }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
  end

  def pdf_upload(lines, name)
    file = Tempfile.new([ "bill", ".pdf" ], binmode: true)
    file.write(Prawn::Document.new { |doc| lines.each { |line| doc.text line } }.render)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/pdf", true, original_filename: name)
  end

  def amazon_pdf(number: "1987654321", total: "$1,284.37", month: "January")
    pdf_upload([ "Amazon Web Services Invoice", "Invoice Number: #{number}", "Invoice Date: February 2 , 2026",
                 "This invoice is for the billing period #{month} 1 - #{month} 31 , 2026", "Total for this invoice #{total}",
                 "Detail", "Amazon Elastic Compute Cloud #{total}" ], "aws-#{number}.pdf")
  end

  def claude_pdf
    pdf_upload([ "Receipt", "Receipt number 2069-5479-2866", "Date paid October 20, 2026", "Anthropic, PBC", "Amount paid $181.18" ], "claude-oct.pdf")
  end

  it "is for superadmins only" do
    sign_in(regular_user)
    get finances_costs_path
    expect(response).to redirect_to(my_dashboard_path)
    post finances_costs_upload_path, params: { files: [ amazon_pdf ] }
    expect(CompanyExpense.count).to eq(0)
  end

  describe "as a superadmin" do
    before { sign_in(superadmin_user) }

    it "reads uploaded bills, and counts none of them until each is confirmed" do
      post finances_costs_upload_path, params: { files: [ amazon_pdf, claude_pdf ], paid_by: "company", share_percent: "100" }
      expect(response).to redirect_to(finances_costs_path)
      expect(CompanyExpense.to_check.pluck(:vendor, :bill_total_cents, :period_month))
        .to contain_exactly([ "Amazon", 128_437, Date.new(2026, 1, 1) ], [ "Anthropic", 18_118, Date.new(2026, 10, 1) ])
      expect(CompanyExpense.confirmed).to be_empty
      expect(CocoScoutMoneyNow.new(check: nil).outside_cost_cents).to eq(0)

      get finances_costs_path
      expect(response.body).to include("2 bills to check", "Open aws-1987654321.pdf", "Confirm all 2", "CocoScout only", "No bills for #{Date.current.year} yet")

      # The Claude receipt is one the company reimburses half of.
      claude = CompanyExpense.find_by!(vendor: "Anthropic")
      patch finances_cost_path(claude), params: { confirm: "1", company_expense: { vendor: "Anthropic", category: "software", bill_total: "181.18",
                                                                                   share_percent: "50", period_month: "2026-10", paid_by: "reimbursed" } }
      expect(claude.reload).to have_attributes(amount_cents: 9_059, paid_by: "reimbursed", confirmed?: true)

      post finances_costs_confirm_all_path
      expect(CompanyExpense.to_check).to be_empty
      expect(CocoScoutMoneyNow.new(check: nil).outside_cost_cents).to eq(128_437 + 9_059)

      get finances_costs_path(year: 2026)
      expect(response.body).to include("Spent in 2026", "$1,374.96", "Every bill in 2026", "50% of $181.18", "Tim, reimbursed", "By service",
                                       "Download 2026 for the CPA")
      expect(response.body).not_to include("to check")
    end

    it "won't take the same bill twice" do
      post finances_costs_upload_path, params: { files: [ amazon_pdf ] }
      post finances_costs_upload_path, params: { files: [ amazon_pdf ] }
      expect(CompanyExpense.count).to eq(1)
      expect(flash[:alert]).to include("Not added", "already here")
    end

    it "takes a cost typed in by hand, corrects it, and removes it" do
      post finances_costs_path, params: { company_expense: { vendor: "Apple", category: "programs", description: "Developer program", bill_total: "99.00",
                                                             share_percent: "100", period_month: "2026-06", paid_by: "company", paid_on: "2026-06-12" } }
      apple = CompanyExpense.last
      expect(apple).to have_attributes(vendor: "Apple", amount_cents: 9_900, period_month: Date.new(2026, 6, 1), paid_on: Date.new(2026, 6, 12), confirmed?: true)

      patch finances_cost_path(apple), params: { company_expense: { vendor: "Apple", category: "programs", bill_total: "106.43", share_percent: "100", period_month: "2026-06" } }
      expect(apple.reload.amount_cents).to eq(10_643)

      delete finances_cost_path(apple)
      expect(CompanyExpense.count).to eq(0)
    end

    it "doesn't nag about months a vendor has no bill for" do
      [ 1, 2, 4, 5 ].each do |month|
        CompanyExpense.create!(vendor: "Amazon", category: "hosting", bill_total_cents: 50_000, period_month: Date.new(2025, month, 1), confirmed_at: Time.current)
      end
      get finances_costs_path(year: 2025)
      expect(response.body).to include("Every bill in 2025")
      expect(response.body).not_to include("Missing from")
    end

    it "counts confirmed bills in Spent and Profit on the CocoScout page, in the month each is for, and not in what's ours in Stripe" do
      this_month = Date.current.beginning_of_month
      CocoScoutLedgerEntry.create!(entry_type: "subscription", amount_cents: 100_000, occurred_at: Time.current)
      CocoScoutLedgerEntry.create!(entry_type: "stripe_fee", amount_cents: -5_000, occurred_at: Time.current, description: "Connect: Active Accounts")
      CompanyExpense.create!(vendor: "Amazon", category: "hosting", bill_total_cents: 30_000, period_month: this_month, confirmed_at: Time.current)
      CompanyExpense.create!(vendor: "Anthropic", category: "software", bill_total_cents: 23_000, share_percent: 50, paid_by: "reimbursed",
                             period_month: this_month.prev_month, confirmed_at: Time.current)
      CompanyExpense.create!(vendor: "Amazon", category: "hosting", bill_total_cents: 77_700, period_month: this_month)

      finances = CocoScoutFinances.new("this_month")
      expect(finances.costs_cents).to eq(-35_000)
      expect(finances.net_cents).to eq(65_000)
      expect(finances.streams.sum { |stream| stream[:net_cents] }).to eq(65_000)
      expect(finances.streams.find { |stream| stream[:key] == :running }[:lines]).to include([ "Amazon (hosting)", -30_000 ])

      monthly = CocoScoutFinances.monthly.index_by { |row| row[:month] }
      expect(monthly[this_month]).to include(spent_cents: 35_000, kept_cents: 65_000)
      expect(monthly[this_month.prev_month]).to include(spent_cents: 11_500, kept_cents: -11_500)

      money = CocoScoutMoneyNow.new(check: nil)
      expect(money.profit_cents).to eq(100_000 - 5_000 - 30_000 - 11_500)
      expect(money.ours_in_stripe_cents).to eq(95_000)

      get finances_path
      expect(response.body).to include("Plus costs paid from our bank, not from Stripe", "$415.00", "Amazon (hosting)", "less $300.00",
                                       "1 uploaded bill", "counted yet")

      get finances_path(period: "this_month", format: :csv)
      expect(response.body).to include("Hosting (paid outside Stripe)", "-300.00")
    end

    it "gives the CPA the year as a file, and with every receipt in one zip, marked CocoScout" do
      post finances_costs_upload_path, params: { files: [ amazon_pdf ] }
      post finances_costs_confirm_all_path

      get finances_costs_export_path(year: 2026)
      expect(response.headers["Content-Disposition"]).to include("CocoScout costs 2026.csv")
      rows = CSV.parse(response.body, headers: true)
      expect(rows.first.to_h).to include("Part of the company" => "CocoScout", "Month it's for" => "2026-01", "Vendor" => "Amazon", "Category" => "Hosting",
                                         "Cost to CocoScout" => "1284.37", "Receipt files" => "2026-01 Amazon 1987654321.pdf")

      get finances_costs_receipts_path(year: 2026)
      names = []
      Zip::File.open_buffer(StringIO.new(response.body)) { |zip| names = zip.entries.map(&:name) }
      expect(names).to contain_exactly("CocoScout costs 2026.csv", "receipts/2026-01 Amazon 1987654321.pdf")

      bill = CompanyExpense.last
      get finances_cost_document_path(bill, attachment_id: bill.documents.first.id)
      expect(response.media_type).to eq("application/pdf")
    end
  end
end
