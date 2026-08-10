# frozen_string_literal: true

require "rails_helper"

# The public /join/:token link — anyone with the link joins the org.
RSpec.describe "Organization join link", type: :request do
  let(:password) { "Password123!" }
  let(:organization) { create(:organization, name: "Big Tent Collective") }

  describe "a brand-new visitor" do
    it "creates the full account, joins the org, and greets them on the dashboard" do
      post do_join_organization_path(organization.invite_token),
           params: { email: "newbie@example.com", password: password }

      user = User.find_by(email_address: "newbie@example.com")
      expect(user).to be_present
      expect(user.default_person).to be_present
      expect(user.default_person.organizations).to include(organization)

      expect(response).to redirect_to(my_dashboard_path)
      follow_redirect!
      expect(response.body).to include("You&#39;ve joined Big Tent Collective")
      # The greeting replaces the generic first-visit hero.
      expect(response.body).not_to include("Welcome to CocoScout!")
    end
  end

  describe "an existing signed-in user" do
    it "joins and gets the same greeting" do
      post handle_signup_path, params: { user: { email_address: "member@example.com", password: password } }

      post do_join_organization_path(organization.invite_token)

      expect(response).to redirect_to(my_dashboard_path)
      follow_redirect!
      expect(response.body).to include("You&#39;ve joined Big Tent Collective")
    end
  end
end
