# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Organizations settings sections", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  context "as the owner" do
    before { sign_in(owner) }

    it "opens on Basic Information with a strip naming every section" do
      get manage_organization_path(org)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Organization Details")
      %w[team locations agreements billing danger].each do |key|
        expect(response.body).to include(section_manage_organization_path(org, section: key))
      end
    end

    it "renders each section on its own URL" do
      {
        "team" => "Team Members",
        "locations" => "Locations",
        "agreements" => "Agreements",
        "billing" => "Billing &amp; Plan",
        "danger" => "Delete"
      }.each do |key, marker|
        get section_manage_organization_path(org, section: key)

        expect(response).to have_http_status(:ok), "expected #{key} to render"
        expect(response.body).to include(marker)
      end
    end

    it "loads only the section it's showing" do
      get section_manage_organization_path(org, section: "locations")

      # The team roster isn't built to render Locations.
      expect(response.body).not_to include("Invite a team member")
    end

    it "sends an unknown section back to the default" do
      get section_manage_organization_path(org, section: "nope")

      expect(response).to redirect_to(manage_organization_path(org))
    end
  end

  context "as a manager who isn't the owner" do
    let(:manager) { create(:user, password: password) }
    let!(:manager_role) { create(:organization_role, :manager, user: manager, organization: org) }

    before { sign_in(manager) }

    it "never offers the Danger Zone, and refuses it if asked for directly" do
      get manage_organization_path(org)
      expect(response.body).not_to include(section_manage_organization_path(org, section: "danger"))

      get section_manage_organization_path(org, section: "danger")
      expect(response).to redirect_to(manage_organization_path(org))
    end
  end
end
