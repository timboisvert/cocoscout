# frozen_string_literal: true

require "rails_helper"

# A production booked by a contract still has a production team (Tim,
# 2026-10-16): the people who signed can be given access to it, so its
# Settings page shows the Production Team tab like any other production's.
RSpec.describe "Production Team on a production booked by a contract", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: manager) }
  let(:production) { create(:production, organization: org, name: "Nuns4Fun Entertainment", production_type: "third_party") }
  let(:partner) { create(:user, password: password) }

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_path
  end

  it "shows the tab, with Tickets, Services and the Danger Zone after it" do
    get edit_manage_production_path(production)
    expect(response).to have_http_status(:ok)
    tabs = response.body.scan(/data-index="(\d+)"[^>]*>\s*([A-Z][A-Za-z ]+)/).map { |index, label| [ index.to_i, label.strip ] }
    expect(tabs).to include([ 3, "Production Team" ], [ 4, "Tickets" ], [ 5, "Services" ], [ 6, "Danger Zone" ])
    expect(response.body.scan('data-tabs-target="panel"').size).to eq(7)
    expect(response.body).not_to include(">Agreement", ">Public Listing", ">Pay")
  end

  it "adds a manager to the production's team" do
    post add_team_member_manage_production_path(production), params: { user_id: partner.id, role: "manager" }
    expect(response).to redirect_to(edit_manage_production_path(production, tab: 3))
    expect(ProductionPermission.find_by(user: partner, production: production)&.role).to eq("manager")
  end

  it "links the production page's Tickets box to the Tickets tab, which moved over one" do
    get manage_production_path(production)
    expect(response.body).to include(%(href="#{edit_manage_production_path(production, tab: 4)}"))
    expect(response.body).not_to include(%(href="#{edit_manage_production_path(production, tab: 3)}"))
  end
end
