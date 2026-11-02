# frozen_string_literal: true

require "rails_helper"

# Money recorded by hand (Books V1.3, plan C2): the Record money sheet,
# the entry it posts, a recorded entry's page, change (restates) and
# remove (reverses). And the Overview's CSV (C3).
RSpec.describe "Manage::MoneyRecords", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Holiday Revue") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  # Record money opens as a modal on the Books page you're on, and saving
  # comes back there (Tim, 2026-11-02).
  it "opens Record money as a modal on any Books section, and comes back after saving" do
    [ manage_money_books_path, *%w[accounts entries shows checks].map { |s| manage_money_books_section_path(section: s) } ].each do |page|
      get page
      expect(response.body).to include('id="record-money-modal"', 'data-modal-id="record-money-modal"', "Moved between your accounts", "Holiday Revue")
    end

    post manage_money_records_path, params: { return_to: "/manage/money/books/entries",
                                              money_record: { kind: "out", on: "2026-10-27", amount: "40.00", category_key: "supplies", via: "bank" } }
    expect(response).to redirect_to("/manage/money/books/entries")
    expect(flash[:notice]).to include("Recorded")

    post manage_money_records_path, params: { return_to: "https://example.org/manage/money/books",
                                              money_record: { kind: "out", on: "2026-10-27", amount: "40.00", category_key: "supplies", via: "bank" } }
    expect(response).to redirect_to(manage_money_record_path(org.money_records.order(:id).last))
  end

  it "opens the sheet with its three tabs, as its own page too" do
    get manage_new_money_record_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Money out", "Money in", "Moved between your accounts", "Holiday Revue")
  end

  it "records money in and puts it on the books as income" do
    post manage_money_records_path, params: { money_record: { kind: "in", on: "2026-10-27", amount: "900.00", category_key: "sponsorship",
                                                                counterparty: "Logan Square Chamber", production_id: production.id, via: "bank", memo: "Check 2210" } }
    record = org.money_records.last
    expect(response).to redirect_to(manage_money_record_path(record))
    expect(record.amount_cents).to eq(90_000)
    expect(record.recorded_by).to eq(owner)
    expect(ChartOfAccounts.account(org, :sponsorship_income).natural_balance_cents).to eq(90_000)
    expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(90_000)

    get manage_money_record_path(record)
    expect(response.body).to include("$900.00", "Sponsorship", "Logan Square Chamber", "Holiday Revue, the whole production", "Recorded by hand")

    get manage_money_books_section_path(section: "entries")
    expect(response.body).to include("Recorded by hand", "Sponsorship · Logan Square Chamber", manage_money_record_path(record))
  end

  it "records money out with a receipt, then a change restates it and a removal reverses it" do
    receipt = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 test"), "application/pdf", original_filename: "receipt-4471.pdf")
    post manage_money_records_path, params: { money_record: { kind: "out", on: "2026-10-30", amount: "412.00", category_key: "production",
                                                                counterparty: "Chicago Lumber Co.", via: "card", receipt: receipt } }
    record = org.money_records.last
    expect(record.receipt).to be_attached
    expect(ChartOfAccounts.account(org, :production_costs).natural_balance_cents).to eq(41_200)
    expect(ChartOfAccounts.account(org, :credit_card).natural_balance_cents).to eq(41_200)

    get manage_edit_money_record_path(record)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("receipt-4471.pdf", "Pick another to replace it")

    patch manage_money_record_path(record), params: { money_record: { amount: "421.00" } }
    expect(response).to redirect_to(manage_money_record_path(record))
    expect(ChartOfAccounts.account(org, :production_costs).natural_balance_cents).to eq(42_100)
    expect(JournalEntry.where(source: record).count).to eq(3) # first, its reversal, the restatement

    get manage_money_record_path(record)
    expect(response.body).to include("receipt-4471.pdf", "An earlier entry was reversed, not edited.")

    delete manage_money_record_path(record)
    expect(response).to redirect_to(manage_money_books_section_path(section: "entries"))
    expect(org.money_records.find_by(id: record.id)).to be_nil
    expect(ChartOfAccounts.account(org, :production_costs).natural_balance_cents).to eq(0)
    expect(ChartOfAccounts.account(org, :credit_card).natural_balance_cents).to eq(0)
  end

  it "records a move between door cash and the bank, without touching income or spending" do
    post manage_money_records_path, params: { money_record: { kind: "move", on: "2026-10-25", amount: "340", from_account: "door_cash", to_account: "bank" } }
    expect(ChartOfAccounts.account(org, :bank).natural_balance_cents).to eq(34_000)
    expect(ChartOfAccounts.account(org, :door_cash).natural_balance_cents).to eq(-34_000)
    expect(BooksReport.new(org).overview(range: Date.new(2026, 10, 1)..Date.new(2026, 10, 31))).to be_empty
  end

  it "refuses a move from an account to itself and an amount of nothing" do
    post manage_money_records_path, params: { money_record: { kind: "move", on: "2026-10-25", amount: "0", from_account: "bank", to_account: "bank" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(org.money_records.count).to eq(0)
  end

  it "downloads the period as a CSV, one row per line" do
    post manage_money_records_path, params: { money_record: { kind: "in", on: "2026-10-27", amount: "900.00", category_key: "sponsorship", counterparty: "Logan Square Chamber", production_id: production.id, via: "bank" } }
    travel_to Time.zone.local(2026, 10, 31, 12) do
      get manage_money_books_download_path(period: "this_month")
    end
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("books-this-month-when-earned.csv")
    rows = CSV.parse(response.body)
    expect(rows.first).to eq([ "Earned on", "Moved on", "What", "Description", "Category", "Production", "Show", "In", "Out" ])
    expect(rows.last).to eq([ "2026-10-27", "2026-10-27", "Recorded by hand", "Sponsorship · Logan Square Chamber", "Sponsorship", "Holiday Revue", nil, "900.00", nil ])
  end

  it "lets a bookkeeper with view-only Books look but not record" do
    viewer = create(:user, password: password)
    create(:organization_role, user: viewer, organization: org, company_role: "viewer").update!(module_grants: { "books" => "view" })
    get signout_path
    post handle_signin_path, params: { email_address: viewer.email_address, password: password }

    get manage_money_books_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(manage_new_money_record_path)
    get manage_new_money_record_path
    expect(response).to redirect_to(manage_money_books_path)
    post manage_money_records_path, params: { money_record: { kind: "in", on: "2026-10-27", amount: "9", category_key: "other", via: "bank" } }
    expect(org.money_records.count).to eq(0)
  end
end
