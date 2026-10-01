# frozen_string_literal: true

require "rails_helper"

# The read-only Books page: balances, entries and what caused them, ticket
# money by show, and the checks. Superadmins only while ticketing is tested.
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
    expect(response.body).to include("Money you have", "CocoScout balance", "$44.10", "Tickets sold for upcoming shows", "$40.00",
                                      "Tax to pay the government", "$4.10")

    get manage_money_books_path(basis: "cash")
    expect(response).to have_http_status(:ok)

    balance = ChartOfAccounts.account(org, :cocoscout_balance)
    get manage_money_books_path(tab: "entries", account_id: balance.id)
    expect(response.body).to include("Ticket sale", "Entries touching", manage_ticket_order_path(order.id))

    get manage_money_books_path(tab: "shows")
    expect(response.body).to include("Waiting on the show", "$40.00", "$4.10")

    get manage_money_books_path(tab: "checks")
    expect(response.body).to include("The books balance", "The books agree with the records behind them")
  end

  it "is for superadmins only while it's being tested" do
    sign_in(create(:user, password: password))
    get manage_money_books_path
    expect(response).to redirect_to(manage_path)
  end

  it "says so when nothing's on the books" do
    sign_in(superadmin)
    get manage_money_books_path
    expect(response.body).to include("Nothing's on the books yet")
  end
end
