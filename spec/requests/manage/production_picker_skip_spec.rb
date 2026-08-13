# frozen_string_literal: true

require "rails_helper"

# When an org has exactly one eligible production there is nothing to pick, so
# every "which production?" wizard step 0 jumps straight into the wizard.
RSpec.describe "Production picker skip", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "with exactly one production" do
    it "skips the show wizard picker" do
      get manage_shows_new_wizard_path
      expect(response).to redirect_to(manage_shows_wizard_path(production))
    end

    it "skips the audition cycle wizard picker" do
      get manage_signups_auditions_new_wizard_path
      expect(response).to redirect_to(manage_signups_auditions_wizard_path(production))
    end

    it "skips the sign-up form wizard picker" do
      get manage_signups_forms_new_wizard_path
      expect(response).to redirect_to(manage_signups_forms_wizard_path(production))
    end

    it "skips the casting table wizard picker and seeds the selection" do
      get manage_casting_tables_new_path
      expect(response).to redirect_to(manage_casting_tables_events_path)

      # The events step only renders when a production selection is in state.
      get manage_casting_tables_events_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(production.name)
    end
  end

  describe "with several productions" do
    let!(:second) { create(:production, organization: org, name: "Rising Stars") }

    it "still shows the show wizard picker" do
      get manage_shows_new_wizard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(production.name)
      expect(response.body).to include("Rising Stars")
    end

    it "still shows the audition cycle wizard picker" do
      get manage_signups_auditions_new_wizard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rising Stars")
    end

    it "still shows the sign-up form wizard picker" do
      get manage_signups_forms_new_wizard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rising Stars")
    end

    it "still shows the casting table wizard picker" do
      get manage_casting_tables_new_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rising Stars")
    end
  end

  describe "scope edge cases" do
    it "ignores a course production when counting schedulable ones" do
      create(:production, organization: org, name: "Improv 101", production_type: "course")

      get manage_shows_new_wizard_path
      expect(response).to redirect_to(manage_shows_wizard_path(production))
    end

    it "ignores a third-party production when counting castable ones" do
      create(:production, organization: org, name: "Guest Show", production_type: "third_party")

      get manage_signups_auditions_new_wizard_path
      expect(response).to redirect_to(manage_signups_auditions_wizard_path(production))
    end
  end
end
