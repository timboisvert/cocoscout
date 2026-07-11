# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing::StaffWizard", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:house_role) { org.house_roles.create!(name: "Bartender") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the add-staff wizard" do
    get manage_new_staffing_staff_wizard_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add Staff Member")
    expect(response.body).to include("Hourly rate")
  end

  it "creates a staff member with employment details, a person, and roles" do
    expect {
      post manage_staffing_staff_wizard_path, params: {
        first_name: "Dana", middle_initial: "Q", last_name: "Reed",
        preferred_first_name: "Dee", personal_email: "dee@example.com",
        title: "Bartender", hourly_rate: "22.50", start_date: "2026-08-01",
        house_role_ids: [ house_role.id ]
      }
    }.to change { org.organization_staff_members.count }.by(1)

    member = org.organization_staff_members.order(:created_at).last
    expect(member.first_name).to eq("Dana")
    expect(member.middle_initial).to eq("Q")
    expect(member.preferred_first_name).to eq("Dee")
    expect(member.title).to eq("Bartender")
    expect(member.hourly_rate_cents).to eq(2250)
    expect(member.start_date.to_s).to eq("2026-08-01")
    # Adding a staff member auto-sends the onboarding invite.
    expect(member.onboarding_state).to eq("invited")
    expect(member.house_roles).to include(house_role)
    expect(member.person.email).to eq("dee@example.com")
    expect(member.person.name).to eq("Dana Reed")
    expect(response).to redirect_to(manage_staffing_index_path)
  end

  it "re-renders with an error when required fields are missing" do
    expect {
      post manage_staffing_staff_wizard_path, params: { first_name: "", last_name: "", personal_email: "nope" }
    }.not_to change { org.organization_staff_members.count }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("required")
  end

  it "assigns a manager from an existing staff member" do
    boss_person = create(:person, name: "Boss Person", email: "boss@example.com")
    boss = org.organization_staff_members.create!(person: boss_person, onboarding_state: "added")

    post manage_staffing_staff_wizard_path, params: {
      first_name: "New", last_name: "Hire", personal_email: "hire@example.com", manager_id: boss.id
    }
    member = org.organization_staff_members.find_by!(personal_email: "hire@example.com")
    expect(member.manager).to eq(boss)
  end
end
