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

  let!(:course_production) { create(:production, organization: org, name: "Improv 101", production_type: "course") }
  let!(:course_offering) { create(:course_offering, production: course_production, title: "Improv 101") }
  let!(:registration) { create(:course_registration, course_offering: course_offering, amount_cents: 5000, status: "confirmed") }

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
      # Event links must escape the frame so they don't error with "content missing"
      expect(response.body).to include('data-turbo-frame="_top"')
    end
  end

  describe "courses" do
    it "lists a course as a single row (money in/out/profit), linking to its financials" do
      get manage_money_financials_path
      expect(response.body).to include("Improv 101").and include("Course")
      expect(response.body).to include("1 registration")
      # A course is one row — no expandable events accordion of its own.
      expect(response.body).to include(manage_money_production_financials_path(course_production))
      expect(response.body).not_to include("prod-events-#{course_production.id}")
    end

    it "filters to only courses / only productions" do
      get manage_money_financials_path(type: "courses")
      expect(response.body).to include("Improv 101")
      expect(response.body).not_to include("Slim Revue")

      get manage_money_financials_path(type: "productions")
      expect(response.body).to include("Slim Revue")
      expect(response.body).not_to include("Improv 101")
    end
  end

  describe "the single-production page" do
    it "shows the revenue/costs/profit boxes and the slim events list" do
      get manage_money_production_financials_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Gross Revenue").and include("Direct Costs").and include("Gross Profit")
      expect(response.body).to include(show.display_name)
      expect(response.body).to include(manage_money_show_financials_path(show))
      # No more "Performance vs. Similar Shows" anywhere.
      expect(response.body).not_to include("Performance vs. Similar Shows")
    end
  end

  describe "the course page" do
    it "shows the revenue/costs/profit boxes with a registrations + platform fee breakdown, no session schedule" do
      get manage_money_production_financials_path(course_production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Gross Revenue").and include("Direct Costs").and include("Gross Profit")
      expect(response.body).to include("Registrations").and include("Platform fee")
      expect(response.body).not_to include("Session Schedule")
    end
  end
end
