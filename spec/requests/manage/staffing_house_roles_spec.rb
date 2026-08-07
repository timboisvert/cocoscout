# frozen_string_literal: true

require "rails_helper"

# The roles page owns two things Role Call and the pay run both read: whether a
# per-show role is checked at all, and whether it's priced by the hour or by the
# shift.
RSpec.describe "Manage::Staffing::HouseRoles", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "the Role Call opt-out" do
    it "isn't offered when the org doesn't run Role Call" do
      create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific)

      get manage_staffing_house_roles_path
      expect(response.body).not_to include("Include this role in Role Call")
    end

    it "is offered once Role Call is on" do
      org.update!(alert_uncovered_show_roles: true)
      create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific)

      get manage_staffing_house_roles_path
      expect(response.body).to include("Include this role in Role Call")
    end

    it "marks an opted-out per-show role on its row" do
      org.update!(alert_uncovered_show_roles: true)
      create(:house_role, organization: org, name: "Videographer",
                          role_type: :show_specific, include_in_role_call: false)

      get manage_staffing_house_roles_path
      expect(response.body).to include("Not in Role Call")
    end

    it "a new role is in Role Call unless it says otherwise" do
      post manage_create_staffing_house_role_path,
           params: { house_role: { name: "Booth Tech", role_type: "show_specific", default_required_count: 1 } }

      expect(org.house_roles.find_by(name: "Booth Tech").include_in_role_call).to be(true)
    end

    it "creates a role sitting Role Call out" do
      post manage_create_staffing_house_role_path,
           params: { house_role: { name: "Videographer", role_type: "show_specific",
                                   default_required_count: 1, include_in_role_call: "0" } }

      expect(org.house_roles.find_by(name: "Videographer").include_in_role_call).to be(false)
    end

    it "flips an existing role either way" do
      role = create(:house_role, organization: org, role_type: :show_specific)

      patch manage_update_staffing_house_role_path(role), params: { house_role: { include_in_role_call: "0" } }
      expect(role.reload.include_in_role_call).to be(false)

      patch manage_update_staffing_house_role_path(role), params: { house_role: { include_in_role_call: "1" } }
      expect(role.reload.include_in_role_call).to be(true)
    end
  end

  describe "flat pay reads per shift" do
    it "labels a flat role's rate /shift, never /night" do
      create(:house_role, organization: org, name: "Security",
                          pay_type: "flat", default_flat_rate_cents: 5_000)

      get manage_staffing_house_roles_path
      expect(response.body).to include("$50.00/shift")
      expect(response.body).not_to include("/night")
    end
  end
end
