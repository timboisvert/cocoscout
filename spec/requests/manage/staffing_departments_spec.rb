# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing::Departments", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "lists departments in the manager frame" do
    org.departments.create!(name: "Front of House")
    get manage_staffing_departments_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Front of House")
  end

  it "adds a department" do
    expect {
      post manage_staffing_departments_path, params: { department: { name: "Box Office" } }
    }.to change { org.departments.count }.by(1)
    expect(response).to redirect_to(manage_staffing_departments_path)
  end

  it "removes a department" do
    dept = org.departments.create!(name: "Tech")
    expect {
      delete manage_staffing_department_path(dept)
    }.to change { org.departments.count }.by(-1)
  end

  it "renders the house-roles editor frame" do
    org.house_roles.create!(name: "Bartender")
    get manage_staffing_house_roles_editor_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bartender")
  end

  it "adds a house role from the editor and returns to the editor frame" do
    expect {
      post manage_create_staffing_house_role_path, params: { house_role: { name: "Security" }, return_to: "editor" }
    }.to change { org.house_roles.count }.by(1)
    expect(response).to redirect_to(manage_staffing_house_roles_editor_path)
  end
end
