# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing::StaffWizard", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:house_role) { org.house_roles.create!(name: "Bartender") }

  # The wizard persists step state in Rails.cache, which is the null-store in
  # tests — give it a real in-memory store so the multi-step flow carries over.
  let(:wizard_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(wizard_cache)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  # Walk the multi-step wizard: details → job → manager → start → pay → roles.
  def complete_wizard(details:, job: {}, manager_id: nil, start_date: nil, hourly_rate: nil, role_ids: [])
    post manage_save_details_staffing_staff_wizard_path, params: details
    post manage_save_job_staffing_staff_wizard_path, params: job
    post manage_save_manager_staffing_staff_wizard_path, params: { manager_id: manager_id }
    post manage_save_start_staffing_staff_wizard_path, params: { start_date: start_date }
    post manage_save_pay_staffing_staff_wizard_path, params: { hourly_rate: hourly_rate }
    post manage_staffing_staff_wizard_path, params: { house_role_ids: role_ids }
  end

  it "renders the first step of the add-staff wizard" do
    get manage_new_staffing_staff_wizard_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add Staff Member")
    expect(response.body).to include("Details")
  end

  it "renders the pay step with an hourly rate field" do
    post manage_save_details_staffing_staff_wizard_path, params: {
      first_name: "Dana", last_name: "Reed", personal_email: "dee@example.com"
    }
    get manage_pay_staffing_staff_wizard_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hourly rate")
  end

  it "creates a staff member with employment details, a person, and roles" do
    expect {
      complete_wizard(
        details: { first_name: "Dana", middle_initial: "Q", last_name: "Reed",
                   preferred_first_name: "Dee", personal_email: "dee@example.com" },
        job: { title: "Bartender", department: "Front of House" },
        start_date: "2026-08-01", hourly_rate: "22.50",
        role_ids: [ house_role.id ]
      )
    }.to change { org.organization_staff_members.count }.by(1)

    member = org.organization_staff_members.order(:created_at).last
    expect(member.first_name).to eq("Dana")
    expect(member.middle_initial).to eq("Q")
    expect(member.preferred_first_name).to eq("Dee")
    expect(member.title).to eq("Bartender")
    expect(member.department).to eq("Front of House")
    expect(member.hourly_rate_cents).to eq(2250)
    expect(member.start_date.to_s).to eq("2026-08-01")
    # Adding a staff member auto-sends the onboarding invite.
    expect(member.onboarding_state).to eq("invited")
    expect(member.house_roles).to include(house_role)
    expect(member.person.email).to eq("dee@example.com")
    expect(member.person.name).to eq("Dana Reed")
    expect(response).to redirect_to(manage_staffing_index_path)
  end

  it "re-renders the details step with an error when required fields are missing" do
    expect {
      post manage_save_details_staffing_staff_wizard_path, params: { first_name: "", last_name: "", personal_email: "nope" }
    }.not_to change { org.organization_staff_members.count }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("required")
  end

  it "sends you back to step one if you jump to the end without details" do
    post manage_staffing_staff_wizard_path, params: { house_role_ids: [ house_role.id ] }
    expect(response).to redirect_to(manage_new_staffing_staff_wizard_path)
  end

  it "assigns a manager from an existing staff member" do
    boss_person = create(:person, name: "Boss Person", email: "boss@example.com")
    boss = org.organization_staff_members.create!(person: boss_person, onboarding_state: "added")

    complete_wizard(
      details: { first_name: "New", last_name: "Hire", personal_email: "hire@example.com" },
      manager_id: boss.id
    )
    member = org.organization_staff_members.find_by!(personal_email: "hire@example.com")
    expect(member.manager).to eq(boss)
  end
end
