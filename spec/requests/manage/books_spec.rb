# frozen_string_literal: true

require "rails_helper"

# The Books page: the Overview, then balances, entries and what caused them,
# ticket money by show, and the checks. Open to every Pro manager (V1.3).
RSpec.describe "Manage books", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, owner: superadmin) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  def sign_in(user)
    create(:organization_role, :manager, user: user, organization: org)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    get manage_path
  end

  def sell(count)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    TicketOrderSettlement.settle!(order)
    order
  end

  it "shows balances, the entries behind them, ticket money by show, and the checks" do
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    order = sell(2)
    sign_in(superadmin)

    get manage_money_books_path
    expect(response.body).to include("All your money, wherever it sits", "CocoScout balance", "Waiting on upcoming shows")
    # The sections are cards on the landing page, the way Money has them.
    expect(response.body).to include("data-module-header", manage_money_books_section_path(section: "accounts"), manage_money_statements_path, manage_money_taxes_path, manage_money_bank_path)

    get manage_money_books_section_path(section: "accounts")
    expect(response.body).to include(manage_money_books_path) # the breadcrumb back
    expect(response.body).to include("Money you have", "CocoScout balance", "$44.10", "Tickets sold for upcoming shows", "$40.00",
                                      "Tax to pay the government", "$4.10")

    get manage_money_books_path(basis: "cash")
    expect(response).to have_http_status(:ok)

    balance = ChartOfAccounts.account(org, :cocoscout_balance)
    get manage_money_books_section_path(section: "entries", account_id: balance.id)
    expect(response.body).to include("Ticket sale", "Entries touching", manage_ticket_order_path(order.id))

    get manage_money_books_section_path(section: "shows")
    expect(response.body).to include("Waiting on the show", "$40.00", "$4.10")

    get manage_money_books_section_path(section: "checks")
    expect(response.body).to include("The books balance", "The books agree with the records behind them", "Financials and Books")
  end

  it "says how the checks stand from the last time they ran, and runs them again on the Checks page and overnight" do
    sell(2)
    sign_in(superadmin)
    allow(BooksReconciliation).to receive(:check).and_call_original

    # The first look at Books runs them once and keeps the answer.
    get manage_money_books_path
    expect(response.body).to include("The books agree with every record behind them")
    expect(BooksReconciliation.last_run_at(org.reload)).to be_present
    expect(BooksReconciliation).to have_received(:check).once

    # After that a Books page reads what was kept, and never runs them.
    get manage_money_books_path
    get manage_money_books_section_path(section: "accounts")
    get manage_money_books_section_path(section: "entries")
    expect(BooksReconciliation).to have_received(:check).once

    # A tax payment the books never heard about: the kept answer stands
    # until the checks run again, on the Checks page or overnight.
    SalesTaxRemittance.insert!({ organization_id: org.id, tax_name: "Sales tax", rate_bps: 1_025, period_start: Date.current.beginning_of_month,
                                 period_end: Date.current.end_of_month, paid_on: Date.current, amount_cents: 100, created_at: Time.current, updated_at: Time.current })
    get manage_money_books_path
    expect(response.body).to include("The books agree with every record behind them")
    get manage_money_books_section_path(section: "checks")
    expect(response.body).to include("1 account disagree with the records behind them")
    get manage_money_books_path
    expect(response.body).to include("1 account disagree with the records behind them")

    org.update_column(:books_check, {})
    BooksReconciliationJob.perform_now
    expect(BooksReconciliation.last(org.reload).map(&:account)).to eq([ "tax_to_remit" ])
  end

  it "pages ticket money by show, newest first, adding up only the page's shows" do
    production = create(:production, organization: org)
    older = create(:show, production: production, date_and_time: Time.zone.local(2026, 3, 6, 20))
    newer = create(:show, production: production, date_and_time: Time.zone.local(2026, 9, 4, 20))
    elsewhere = create(:show, date_and_time: Time.zone.local(2026, 9, 5, 20))
    { older => 11_100, newer => 22_200 }.each do |show, cents|
      LedgerPosting.post!(organization: org, source: nil, kind: "sale", entry_date: show.date_and_time.to_date,
                          lines: [ { account: :cocoscout_balance, amount_cents: cents, show: show }, { account: :ticket_income, amount_cents: -cents, show: show } ])
    end
    stub_const("Manage::BooksController::SHOWS_PER_PAGE", 1)
    sign_in(superadmin)

    report = BooksReport.new(org)
    expect(report.shows_with_ticket_money.to_a).to eq([ newer, older ])
    expect(report.by_show.map { |row| [ row.show, row.income_cents ] }).to eq([ [ newer, 22_200 ], [ older, 11_100 ] ])
    expect(report.by_show([ older ]).map(&:income_cents)).to eq([ 11_100 ])
    expect(BooksReport.new(elsewhere.production.organization).shows_with_ticket_money).to be_empty

    get manage_money_books_section_path(section: "shows")
    expect(response.body).to include("Sep 4, 2026", "$222.00", "Page 1 of 2", manage_money_books_section_path(section: "shows", page: 2))
    expect(response.body).not_to include("$111.00")

    get manage_money_books_section_path(section: "shows", page: 2)
    expect(response.body).to include("Mar 6, 2026", "$111.00", "Page 2 of 2")
    expect(response.body).not_to include("$222.00")
  end

  it "opens for any manager of a Pro organization" do
    sign_in(create(:user, password: password))
    get manage_money_books_path
    expect(response).to have_http_status(:ok)
  end

  it "says so when nothing's on the books" do
    sign_in(superadmin)
    get manage_money_books_path(period: "all_time")
    expect(response.body).to include("Nothing on the books for all time")
    get manage_money_books_section_path(section: "accounts")
    expect(response.body).to include("Nothing on the books yet")
    get manage_money_books_path(tab: "accounts") # the old address still answers
    expect(response.body).to include("Nothing on the books yet")
  end

  it "shows the period's money in and out on the Overview, by week and by production" do
    sell(2)
    sign_in(superadmin)
    get manage_money_books_path(period: "all_time", basis: "cash")
    expect(response).to have_http_status(:ok)
    get manage_money_books_path(period: "this_month", production: listing.production_id)
    expect(response).to have_http_status(:ok)
  end
end
