# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Money (hub)", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Hub Revue") }
  let!(:show) do
    create(:show, production: production, event_type: :show, date_and_time: 3.days.ago).tap do |s|
      create(:show_financials, :complete, show: s, ticket_revenue: 1500.0)
    end
  end
  let!(:course_production) { create(:production, organization: org, name: "Hub Course", production_type: "course") }
  let!(:course_offering) { create(:course_offering, production: course_production, title: "Hub Course") }
  let!(:registration) { create(:course_registration, course_offering: course_offering, amount_cents: 5000, status: "confirmed") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "shows the 3 money boxes (no Contract Revenue card) and the slim grid" do
    get manage_money_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Money In").and include("Money Out").and include("Profit")
    expect(response.body).not_to include("Contract Revenue")
    # Slim grid: production expands to events, course listed too.
    expect(response.body).to include("Hub Revue")
    expect(response.body).to include("prod-events-#{production.id}")
    expect(response.body).to include("Hub Course")
  end
end
