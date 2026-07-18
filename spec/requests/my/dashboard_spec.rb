# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Dashboard", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  describe "staff onboarding prompts" do
    it "prompts to finish onboarding for an incomplete staff position, linking to that org's onboarding" do
      org = create(:organization, :pro)
      create(:organization_staff_member, organization: org, person: person, onboarding_state: "invited")

      get my_dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Finish setting up your staff")
      expect(response.body).to include(org.name)
      expect(response.body).to include(my_onboarding_path(org.id))
    end

    it "shows a separate prompt per organization" do
      org_a = create(:organization, :pro, name: "Alpha Theater")
      org_b = create(:organization, :pro, name: "Beta Playhouse")
      create(:organization_staff_member, organization: org_a, person: person, onboarding_state: "invited")
      create(:organization_staff_member, organization: org_b, person: person, onboarding_state: "invited")

      get my_dashboard_path
      expect(response.body).to include("Alpha Theater").and include("Beta Playhouse")
      expect(response.body).to include(my_onboarding_path(org_a.id)).and include(my_onboarding_path(org_b.id))
    end

    it "does not prompt once onboarding is complete (accepted + bank connected)" do
      person.update!(stripe_account_id: "acct_x", payouts_enabled: true)
      org = create(:organization, :pro)
      create(:organization_staff_member, organization: org, person: person,
                                         onboarding_state: "invited", acknowledged_at: Time.current)

      get my_dashboard_path
      expect(response.body).not_to include("Finish setting up your staff")
    end
  end
end
