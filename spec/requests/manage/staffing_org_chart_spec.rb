# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing org chart", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the org chart with staff and their reports" do
    boss_person = create(:person, name: "Boss Bianca")
    boss = create(:organization_staff_member, organization: org, person: boss_person, title: "GM")
    report_person = create(:person, name: "Report Rudy")
    create(:organization_staff_member, organization: org, person: report_person, manager: boss)

    get manage_staffing_org_chart_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Boss Bianca").and include("Report Rudy")
  end

  it "shows an empty state with no staff" do
    get manage_staffing_org_chart_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No staff yet")
  end
end
