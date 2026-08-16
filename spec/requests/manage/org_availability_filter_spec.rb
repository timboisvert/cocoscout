# frozen_string_literal: true

require "rails_helper"

# /manage/casting/availability used to hand-roll its own production <select>.
# It now uses the shared filter bar and production dropdown, like every other
# org-level list — including carrying the time range through the links.
RSpec.describe "Manage::Casting availability filter bar", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "The Late Show") }
  let!(:other_production) { create(:production, organization: org, name: "Midnight Matinee") }
  let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }
  let(:person) { create(:person, name: "Avail Abby") }

  before do
    org.people << person
    create(:talent_pool_membership, talent_pool: production.talent_pool, member: person)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "renders the shared production dropdown instead of a bare select" do
    get manage_org_availability_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("All Productions")
    expect(response.body).to include("The Late Show")
    expect(response.body).to include("Midnight Matinee")
    expect(response.body).to include('data-controller="production-dropdown"')
  end

  it "keeps the time range when you pick a production" do
    get manage_org_availability_path(months: 12)

    expect(response.body).to include("months=12&amp;production_id=#{production.id}")
  end

  it "keeps the chosen production when you change the time range" do
    get manage_org_availability_path(production_id: production.id)

    expect(response.body).to include(CGI.escapeHTML(manage_org_availability_path(months: 12, production_id: production.id)))
  end

  it "still filters the grid down to the chosen production" do
    get manage_org_availability_path(production_id: production.id)

    expect(response.body).to include("The Late Show")
    expect(response.body).not_to include("Midnight Matinee</span>")
  end
end
