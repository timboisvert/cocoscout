# frozen_string_literal: true

require "rails_helper"

# The course wizard's schedule step is preceded by a "where does the schedule
# come from?" page for Pro orgs (contract-linked scheduling is a Pro feature).
# Producer-plan orgs skip that page and go straight to the manual schedule.
RSpec.describe "Course wizard schedule source", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  # The wizard stores its state in Rails.cache, which is :null_store in test —
  # swap in a real store so the seeded state survives across requests.
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    Rails.cache.write(
      "course_offering_wizard:#{owner.id}:#{org.id}",
      { title: "Test Course" },
      expires_in: 1.hour
    )
  end

  context "on the Pro plan with an active contract" do
    let!(:org) { create(:organization, :pro, owner: owner) }
    let!(:contract) { create(:contract, organization: org, status: :active) }

    it "routes the instructor step to the schedule-source page" do
      post manage_course_wizard_instructor_path
      expect(response).to redirect_to(manage_course_wizard_schedule_source_path)
    end

    it "offers both schedule sources" do
      get manage_course_wizard_schedule_source_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Part of an existing contract")
      expect(response.body).to include("A fresh schedule")
    end

    it "choosing the contract source shows the contract picker on the schedule page" do
      post manage_course_wizard_schedule_source_path, params: { schedule_source: "contract" }
      expect(response).to redirect_to(manage_course_wizard_schedule_path)

      get manage_course_wizard_schedule_path
      expect(response.body).to include("Select Contract")
      expect(response.body).not_to include("Session dates")
    end

    it "choosing a fresh schedule shows the manual session builder" do
      post manage_course_wizard_schedule_source_path, params: { schedule_source: "independent" }
      get manage_course_wizard_schedule_path
      expect(response.body).to include("Session dates")
      expect(response.body).not_to include("Select Contract")
    end

    it "switching back to a fresh schedule clears any stored contract link" do
      Rails.cache.write(
        "course_offering_wizard:#{owner.id}:#{org.id}",
        { title: "Test Course", schedule_mode: "contract", contract_id: contract.id, selected_show_ids: [ 1 ] },
        expires_in: 1.hour
      )
      post manage_course_wizard_schedule_source_path, params: { schedule_source: "independent" }
      state = Rails.cache.read("course_offering_wizard:#{owner.id}:#{org.id}").with_indifferent_access
      expect(state[:schedule_mode]).to eq("independent")
      expect(state[:contract_id]).to be_nil
      expect(state[:selected_show_ids]).to be_nil
    end
  end

  context "on the Pro plan with no active contracts" do
    let!(:org) { create(:organization, :pro, owner: owner) }

    it "still shows the page, with the contract option unavailable" do
      get manage_course_wizard_schedule_source_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("any active contracts yet")
    end

    it "cannot force contract mode without a contract" do
      post manage_course_wizard_schedule_source_path, params: { schedule_source: "contract" }
      state = Rails.cache.read("course_offering_wizard:#{owner.id}:#{org.id}").with_indifferent_access
      expect(state[:schedule_mode]).to eq("independent")
    end
  end

  context "on the Producer (free) plan" do
    let!(:org) { create(:organization, owner: owner) }
    let!(:contract) { create(:contract, organization: org, status: :active) }

    it "routes the instructor step straight to the schedule page" do
      post manage_course_wizard_instructor_path
      expect(response).to redirect_to(manage_course_wizard_schedule_path)
    end

    it "redirects the schedule-source page to the schedule" do
      get manage_course_wizard_schedule_source_path
      expect(response).to redirect_to(manage_course_wizard_schedule_path)
    end

    it "always shows the manual schedule, even with a stored contract mode" do
      Rails.cache.write(
        "course_offering_wizard:#{owner.id}:#{org.id}",
        { title: "Test Course", schedule_mode: "contract", contract_id: contract.id },
        expires_in: 1.hour
      )
      get manage_course_wizard_schedule_path
      expect(response.body).to include("Session dates")
      expect(response.body).not_to include("Select Contract")
    end
  end
end
