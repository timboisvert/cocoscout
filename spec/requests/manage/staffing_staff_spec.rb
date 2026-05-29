# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing::Staff", type: :request do
  let(:password) { "Password123!" }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  describe "access control (owner/manager only)" do
    let(:org) { create(:organization) }

    it "redirects a viewer-level user away" do
      viewer = create(:user, password: password)
      create(:organization_role, user: viewer, organization: org, company_role: "viewer")
      sign_in(viewer)

      get manage_staffing_staff_path
      expect(response).to redirect_to(manage_path)
    end

    it "allows an org manager" do
      manager = create(:user, password: password)
      create(:organization_role, :manager, user: manager, organization: org)
      sign_in(manager)

      get manage_staffing_staff_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /manage/staffing/staff — invite a new person" do
    let(:owner) { create(:user, password: password) }
    let!(:org) { create(:organization, owner: owner) }
    let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
    let!(:house_role) { create(:house_role, organization: org) }

    before { sign_in(owner) }

    it "creates the person, account, staff membership with roles, and an invitation" do
      expect {
        post manage_create_staffing_staff_path, params: {
          invite_email: "NewHire@Example.com",
          invite_name: "New Hire",
          house_role_ids: [house_role.id]
        }
      }.to change(Person, :count).by(1)
        .and change(OrganizationStaffMember, :count).by(1)
        .and change(PersonInvitation, :count).by(1)

      person = Person.find_by(email: "newhire@example.com")
      expect(person).to be_present
      expect(person.user).to be_present
      expect(person.organizations).to include(org)

      member = org.organization_staff_members.find_by(person: person)
      expect(member.house_role_ids).to include(house_role.id)
      expect(response).to redirect_to(manage_staffing_staff_path)
    end

    it "reuses an existing person/account by email" do
      existing = create(:person, email: "existing@example.com", user: create(:user, email_address: "existing@example.com"))

      expect {
        post manage_create_staffing_staff_path, params: {
          invite_email: "existing@example.com",
          house_role_ids: [house_role.id]
        }
      }.to change(OrganizationStaffMember, :count).by(1)
        .and change(Person, :count).by(0)

      expect(org.organization_staff_members.find_by(person: existing)).to be_present
    end

    it "rejects an invalid email without creating a staff member" do
      expect {
        post manage_create_staffing_staff_path, params: { invite_email: "not-an-email", invite_name: "X" }
      }.not_to change(OrganizationStaffMember, :count)
      expect(response).to redirect_to(manage_staffing_staff_path)
    end
  end
end
