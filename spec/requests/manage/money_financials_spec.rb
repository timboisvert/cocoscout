# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::MoneyFinancials", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Slim Revue") }
  let!(:show) do
    create(:show, production: production, event_type: :show, date_and_time: 3.days.ago).tap do |s|
      create(:show_financials, :complete, show: s, ticket_revenue: 1500.0)
    end
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "the all-productions slim list" do
    it "renders productions in the slim spreadsheet list with an expandable events frame" do
      get manage_money_financials_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Slim Revue")
      # The slim list header columns
      expect(response.body).to include("Revenue").and include("Costs").and include("Profit")
      # Each row is an accordion with a lazy Turbo frame pointing at its events
      expect(response.body).to include("prod-events-#{production.id}")
      expect(response.body).to include(manage_money_production_financial_events_path(production))
    end
  end

  describe "the lazy events frame" do
    it "renders slim revenue-event rows inside a matching Turbo frame" do
      get manage_money_production_financial_events_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-frame")
      expect(response.body).to include("prod-events-#{production.id}")
      expect(response.body).to include(show.display_name)
      expect(response.body).to include(manage_money_show_financials_path(show))
    end
  end
end
