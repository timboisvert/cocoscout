# frozen_string_literal: true

require "rails_helper"

# The Money hub is a to-do page, not a browse page: the org's headline numbers,
# then what still needs doing about financials, payouts and money owed to us,
# then links out to the full grids.
RSpec.describe "Manage::Money (hub)", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Hub Revue") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "keeps the org summary and sends the grids to All Financials" do
    create(:show, production: production, event_type: :show, date_and_time: 3.days.ago).tap do |s|
      create(:show_financials, :complete, show: s, ticket_revenue: 1500.0)
    end

    get manage_money_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Gross Revenue").and include("Direct Costs").and include("Gross Profit")
    expect(response.body).not_to include("Contract Revenue")

    # The per-production grid moved off this page entirely.
    expect(response.body).not_to include("prod-events-#{production.id}")
    expect(response.body).to include(manage_money_all_financials_path(type: "productions"))
    expect(response.body).to include(manage_money_all_financials_path(type: "courses"))
  end

  it "says you're caught up rather than hiding a finished section" do
    get manage_money_index_path

    expect(response.body).to include("You&#39;re all caught up on financials.")
    expect(response.body).to include("Nothing waiting to be paid.")
    expect(response.body).to include("Nothing owed to you in the next 30 days.")
    # Even caught up, each section still offers its page.
    expect(response.body).to include(manage_money_financials_path)
    expect(response.body).to include(manage_money_payouts_path)
  end

  it "lists shows that still need financials, and links through to Financials" do
    show = create(:show, production: production, event_type: :show, date_and_time: 2.days.ago)

    get manage_money_index_path
    expect(response.body).to include("Needs financials")
    expect(response.body).to include(manage_money_show_financials_path(show))
    expect(response.body).not_to include("You&#39;re all caught up on financials.")
  end

  # A future show hasn't happened, a canceled one never will, and a confirmed
  # one is done — none of them are work.
  it "counts only shows that are actually outstanding" do
    create(:show, production: production, event_type: :show, date_and_time: 2.days.from_now)
    create(:show, production: production, event_type: :show, date_and_time: 2.days.ago, canceled: true)
    create(:show, production: production, event_type: :show, date_and_time: 2.days.ago).tap do |s|
      create(:show_financials, :complete, show: s, ticket_revenue: 100.0)
    end

    get manage_money_index_path
    expect(response.body).to include("You&#39;re all caught up on financials.")
  end
end
