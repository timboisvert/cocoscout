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

  # An org that has never entered financials has one of these rows for every
  # show it has ever run. The list gets capped; the count above it does not.
  describe "a Needs Financials list longer than the page shows" do
    it "caps the rows, keeps the count honest, and says so" do
      limit = Manage::MoneyFinancialsController::AWAITING_FINANCIALS_LIMIT
      extra = create(:production, organization: org, name: "Backlog Revue")
      (limit + 4).times do |i|
        create(:show, production: extra, event_type: :show, date_and_time: (i + 2).days.ago)
      end

      get manage_money_financials_path

      # The fixture show at the top of this file already has confirmed
      # financials, so it isn't in the list — these 104 are the new ones.
      expect(response.body).to include("(#{limit + 4})")
      expect(response.body).to include("Showing the #{limit} most recent of #{limit + 4}")
      expect(response.body).to include(manage_money_all_financials_path(filter: "pending"))
    end

    it "says nothing about truncation when everything fits" do
      get manage_money_financials_path
      expect(response.body).not_to include("most recent of")
    end
  end

  # The grid used to run a whole FinancialSummaryService pass per production —
  # and the org-wide summary above it had already queried the same shows. What
  # matters isn't the absolute count but that adding productions doesn't add
  # queries.
  describe "the cost of the All Financials page" do
    it "doesn't grow with the number of productions" do
      get manage_money_all_financials_path # warm the route/view caches
      baseline = count_queries { get manage_money_all_financials_path }

      8.times do |i|
        extra = create(:production, organization: org, name: "Extra #{i}")
        s = create(:show, production: extra, event_type: :show, date_and_time: 4.days.ago)
        create(:show_financials, :complete, show: s, ticket_revenue: 200.0)
      end
      scaled = count_queries { get manage_money_all_financials_path }

      expect(scaled - baseline).to be <= 5
    end
  end

  describe "the all-productions slim list" do
    it "keeps the index action-focused with a link to All financials" do
      get manage_money_financials_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(manage_money_all_financials_path)
    end

    it "says you're all caught up when no show is owing financials, instead of a bare gap" do
      ShowFinancials.where(show: Show.joins(:production).where(productions: { organization_id: org.id })).destroy_all
      Show.joins(:production).where(productions: { organization_id: org.id }).update_all(date_and_time: 2.weeks.from_now)
      get manage_money_financials_path
      expect(response.body).to include("You're all caught up on financials")
      expect(response.body).not_to include("Needs Financials")
    end

    it "renders productions in the slim spreadsheet list with an expandable events frame (All Financials page)" do
      get manage_money_all_financials_path
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
      get manage_money_all_financials_path
      expect(response.body).to include("Improv 101").and include("Course")
      expect(response.body).to include("1 registration")
      # A course is one row — no expandable events accordion of its own.
      expect(response.body).to include(manage_money_production_financials_path(course_production))
      expect(response.body).not_to include("prod-events-#{course_production.id}")
    end

    it "filters to only courses / only productions" do
      get manage_money_all_financials_path(type: "courses")
      expect(response.body).to include("Improv 101")
      expect(response.body).not_to include("Slim Revue")

      get manage_money_all_financials_path(type: "productions")
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
    it "shows the revenue/costs/profit boxes and a payouts link — no multi-row breakdown or session schedule" do
      get manage_money_production_financials_path(course_production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Gross Revenue").and include("Direct Costs").and include("Gross Profit")
      expect(response.body).to include("Manage course payouts")
      # The confusing per-line breakdown is gone.
      expect(response.body).not_to include("Platform fee")
      expect(response.body).not_to include("Session Schedule")
    end
  end
end
