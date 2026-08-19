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

  # Walk the restructured wizard: details → job → manager → start → roles →
  # review → invite (create a new CocoScout person) → agreement → send. The
  # member is persisted at the Invite step; the onboarding invite goes at Send.
  def complete_wizard(details:, job: {}, manager_id: nil, start_date: nil, role_ids: [], email: {})
    post manage_save_details_staffing_staff_wizard_path, params: details
    post manage_save_job_staffing_staff_wizard_path, params: job
    post manage_save_manager_staffing_staff_wizard_path, params: { manager_id: manager_id }
    post manage_save_start_staffing_staff_wizard_path, params: { start_date: start_date }
    post manage_save_roles_staffing_staff_wizard_path, params: { house_role_ids: role_ids }
    post manage_staffing_staff_wizard_path # save_review → advances to Invite
    post manage_invite_new_person_staffing_staff_wizard_path, params: {
      first_name: details[:first_name], last_name: details[:last_name],
      middle_initial: details[:middle_initial], email: details[:personal_email]
    }
    post manage_save_invite_staffing_staff_wizard_path # persists the member + roles
    post manage_save_agreement_staffing_staff_wizard_path # optional template pick
    post manage_save_send_staffing_staff_wizard_path, params: email # sends the invite
  end

  it "renders the first step of the add-staff wizard" do
    get manage_new_staffing_staff_wizard_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add Staff Member")
    expect(response.body).to include("Details")
  end

  it "creates a staff member with employment details, a person, and roles" do
    expect {
      complete_wizard(
        details: { first_name: "Dana", middle_initial: "Q", last_name: "Reed",
                   preferred_first_name: "Dee", personal_email: "dee@example.com" },
        job: { title: "Bartender", department: "Front of House" },
        start_date: "2026-08-01",
        role_ids: [ house_role.id ]
      )
    }.to change { org.organization_staff_members.count }.by(1)

    member = org.organization_staff_members.order(:created_at).last
    expect(member.first_name).to eq("Dana")
    expect(member.middle_initial).to eq("Q")
    expect(member.preferred_first_name).to eq("Dee")
    expect(member.title).to eq("Bartender")
    expect(member.department).to eq("Front of House")
    expect(member.start_date.to_s).to eq("2026-08-01")
    # Adding a staff member auto-sends the onboarding invite.
    expect(member.onboarding_state).to eq("invited")
    expect(member.house_roles).to include(house_role)
    expect(member.person.email).to eq("dee@example.com")
    expect(member.person.name).to eq("Dana Reed")
    expect(response).to redirect_to(manage_staffing_index_path)
  end

  it "asks for a flat-pay role's rate per shift and an hourly role's per hour, on the roles step, the review and the edit page" do
    security = org.house_roles.create!(name: "Door Security", pay_type: "flat", default_flat_rate_cents: 5000)
    house_role.update!(default_hourly_rate_cents: 2000)

    post manage_save_details_staffing_staff_wizard_path, params: { first_name: "Dana", last_name: "Reed", personal_email: "dee@example.com" }
    get manage_roles_staffing_staff_wizard_path
    expect(response.body).to include(%(data-role-id="#{security.id}"))
    expect(response.body).to include("Role default $50.00/shift")
    expect(response.body).to include("Role default $20.00/hr")

    post manage_save_roles_staffing_staff_wizard_path,
         params: { house_role_ids: [ security.id, house_role.id ], role_rates: { security.id => "60", house_role.id => "22" } }
    get manage_review_staffing_staff_wizard_path
    expect(response.body).to include("$60.00/shift")
    expect(response.body).to include("$22.00/hr")

    # The manage-roles frame tells the client which unit each role uses too
    get manage_staffing_house_roles_editor_path
    expect(response.body).to include(%(data-role-unit="/shift"))
    expect(response.body).to include(%(data-role-unit="/hr"))

    # And once they're a member, the edit page seeds the flat role's field with its per-shift amount
    post manage_staffing_staff_wizard_path
    post manage_invite_new_person_staffing_staff_wizard_path, params: { first_name: "Dana", last_name: "Reed", email: "dee@example.com" }
    post manage_save_invite_staffing_staff_wizard_path
    member = org.organization_staff_members.order(:id).last
    expect(member.flat_cents_for(security)).to eq(6000)
    expect(member.rate_cents_for(house_role)).to eq(2200)
    get manage_edit_staffing_staff_path(member)
    expect(response.body).to match(/name="role_rates\[#{security.id}\]"\s+value="60\.00"/)
    expect(response.body).to match(/name="role_rates\[#{house_role.id}\]"\s+value="22\.00"/)
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

  it "renders the review step summarizing the entry" do
    post manage_save_details_staffing_staff_wizard_path, params: {
      first_name: "Dana", last_name: "Reed", preferred_first_name: "Dee", personal_email: "dee@example.com"
    }
    post manage_save_job_staffing_staff_wizard_path, params: { title: "Bartender" }
    get manage_review_staffing_staff_wizard_path
    expect(response).to have_http_status(:ok)
    # Review is a read-only summary; the invite/agreement/send happen after it.
    expect(response.body).to include("Review the setup")
    expect(response.body).to include("Dana Reed").and include("Bartender")
  end

  it "sends the reviewer's edited invitation copy" do
    complete_wizard(
      details: { first_name: "Dana", last_name: "Reed", personal_email: "dee@example.com" },
      email: { email_subject: "Welcome to the team!", email_body: "<p>Come on in, Dana.</p>" }
    )
    msg = Message.order(:created_at).last
    expect(msg.subject).to eq("Welcome to the team!")
    expect(msg.body.to_plain_text).to include("Come on in, Dana")
  end

  it "assigns a manager from an existing staff member" do
    boss_person = create(:person, name: "Boss Person", email: "boss@example.com")
    boss = org.organization_staff_members.create!(person: boss_person, onboarding_state: "added")

    complete_wizard(
      details: { first_name: "New", last_name: "Hire", personal_email: "hire@example.com" },
      manager_id: boss.id
    )
    member = org.organization_staff_members.joins(:person).find_by!(people: { email: "hire@example.com" })
    expect(member.manager).to eq(boss)
  end
end
