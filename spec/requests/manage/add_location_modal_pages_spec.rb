# frozen_string_literal: true

require "rails_helper"

# The Add Location modal is a shared partial (manage/locations/_add_location_modal)
# rendered inline on several manage pages. These specs pin that the pages embedding
# it still render, and that the shared partial (not a drifted inline copy) is used.
RSpec.describe "Add Location modal pages", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let!(:location) { create(:location, organization: org) }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  describe "GET audition sessions index" do
    let(:cycle) { create(:audition_cycle, production: production) }

    it "renders the shared Add Location modal" do
      get manage_signups_auditions_cycle_sessions_path(production, cycle)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create a new location for your organization.")
      expect(response.body).to include(%(data-form-url="#{manage_locations_path}"))
    end
  end

  describe "GET audition cycle wizard sessions step" do
    before do
      AuditionWizardState.create!(production: production, user: owner, state: { "allow_in_person_auditions" => true })
    end

    it "renders the shared Add Location modal" do
      get manage_signups_auditions_wizard_sessions_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create a new location for your organization.")
      expect(response.body).to include(%(data-form-url="#{manage_locations_path}"))
    end
  end
end
