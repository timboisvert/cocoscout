# frozen_string_literal: true

require "rails_helper"

# Books → Taxes (V1.3, plan F): one year the way the forms ask.
RSpec.describe "Manage::BooksTaxes", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:year) { Date.current.year }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    org.money_records.create!(kind: "in", on: Date.new(year, 3, 2), amount_cents: 500_000, category_key: "sponsorship", counterparty: "Chamber", via: "bank", recorded_by: owner)
    org.money_records.create!(kind: "out", on: Date.new(year, 3, 9), amount_cents: 120_000, category_key: "venue", counterparty: "Hall", via: "bank", recorded_by: owner)
    org.money_records.create!(kind: "out", on: Date.new(year, 4, 9), amount_cents: 30_000, category_key: "marketing", counterparty: "Ads", via: "card", recorded_by: owner)
  end

  it "summarizes the year the way Schedule C asks, with sales tax and 1099s beside it, and a CSV" do
    get manage_money_taxes_path(year: year)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Gross receipts (Schedule C, Part I)", "Sponsorship", "$5,000.00", "Rent", "$1,200.00", "Advertising", "$300.00", "Net profit", "$3,500.00",
                                     "Sales tax", "Owed on tickets other sites sold", "1099-NECs for #{year}", "Paid to CocoScout")

    get manage_money_taxes_path(year: year, format: :csv)
    expect(response.body).to include("Gross receipts", "Sponsorship,5000.00", "Rent,1200.00", "Net profit,3500.00", "1099s issued,0,0.00")
  end

  it "groups income the 990-EZ way for a nonprofit" do
    org.update!(books_nonprofit: true)
    get manage_money_taxes_path(year: year)
    expect(response.body).to include("Support and revenue (990-EZ, Part I)", "Contributions, gifts and grants", "$5,000.00", "Change in net assets")
  end
end
