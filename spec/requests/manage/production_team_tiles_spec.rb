# frozen_string_literal: true

require "rails_helper"

# The Production team tab: a tile per person with their role and whether the
# production notifies them, and one save for both (Tim, 2026-11-11).
RSpec.describe "Production team tiles", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:production) { create(:production, organization: org) }
  let(:teammate) { create(:user) }
  let(:org_manager) { create(:user) }

  before do
    create(:person, user: teammate, name: "Tess Teammate").tap { |p| teammate.update!(default_person: p) }
    create(:person, user: org_manager, name: "Olive Orgwide").tap { |p| org_manager.update!(default_person: p) }
    create(:organization_role, :manager, user: owner, organization: org)
    create(:organization_role, :manager, user: org_manager, organization: org)
    create(:organization_role, user: teammate, organization: org, company_role: "member")
    ProductionPermission.create!(user: teammate, production: production, role: "viewer")
    ProductionNotificationSetting.create!(production: production, user: teammate, enabled: true)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  def setting(user)
    ProductionNotificationSetting.find_by(production: production, user: user)
  end

  it "shows each person's role and whether they're notified" do
    get edit_manage_production_path(production, tab: 3)

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    tiles = page.css("[data-team-tile]").to_h { |t| [ t["data-user-name"], t ] }
    expect(tiles["Tess Teammate"]["data-role-label"]).to eq("Viewer")
    expect(tiles["Tess Teammate"]["data-notified"]).to eq("true")
    expect(tiles["Tess Teammate"].text).to include("Notified")
    expect(tiles["Olive Orgwide"]["data-role-label"]).to eq("Organization manager")
    expect(tiles["Olive Orgwide"]["data-on-team"]).to eq("false")
    expect(tiles["Olive Orgwide"].text).to include("Not notified")
  end

  it "saves a teammate's role and notifications together" do
    patch update_team_permission_manage_production_path(production),
          params: { user_id: teammate.id, role: "manager", notifications: "0" }

    expect(ProductionPermission.find_by(user: teammate, production: production).role).to eq("manager")
    expect(setting(teammate).enabled).to be(false)
  end

  it "turns an organization manager's notifications on and off without giving them a role here" do
    patch update_team_permission_manage_production_path(production), params: { user_id: org_manager.id, notifications: "1" }
    expect(setting(org_manager).enabled).to be(true)

    patch update_team_permission_manage_production_path(production), params: { user_id: org_manager.id, role: "viewer", notifications: "0" }
    expect(setting(org_manager).enabled).to be(false)
    expect(ProductionPermission.where(user: org_manager, production: production)).to be_empty
  end

  it "refuses someone who isn't on the team" do
    stranger = create(:user)

    patch update_team_permission_manage_production_path(production), params: { user_id: stranger.id, notifications: "1" }

    expect(setting(stranger)).to be_nil
  end
end
