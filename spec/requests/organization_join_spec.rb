# frozen_string_literal: true

require "rails_helper"

# The public /join/:token link — anyone with the link joins the org.
RSpec.describe "Organization join link", type: :request do
  let(:password) { "Password123!" }
  let(:organization) { create(:organization, name: "Big Tent Collective") }

  describe "a brand-new visitor" do
    it "enters their email on the page, creates the account on the sign-in screen, and comes back to join" do
      get join_organization_path(organization.invite_token)
      expect(response.body).to include("Sign in or create an account to join", 'name="signup_token"', 'name="website"')
      expect(response.body).not_to include('type="password" name="password" id="password"')

      complete_signup("newbie@example.com")
      expect(response).to redirect_to(join_organization_path(organization.invite_token))
      follow_redirect!
      expect(response.body).to include("Join Big Tent Collective?")

      post do_join_organization_path(organization.invite_token)
      user = User.find_by!(email_address: "newbie@example.com")
      expect(user.email_verified_at).to be_present
      expect(user.default_person.organizations).to include(organization)

      expect(response).to redirect_to(my_dashboard_path)
      follow_redirect!
      expect(response.body).to include("You&#39;ve joined Big Tent Collective")
      # The greeting replaces the generic first-visit hero.
      expect(response.body).not_to include("Welcome to CocoScout!")
    end

    it "never makes an account from an older copy of the page that posts an email and a password" do
      token = organization.invite_token # made here: the organization brings an owner's account with it
      expect {
        post do_join_organization_path(token), params: { email: "newbie@example.com", password: password }
      }.not_to change(User, :count)

      expect(response).to redirect_to(signin_path(start_over: 1, email_address: "newbie@example.com",
                                                  redirect_to: join_organization_path(organization.invite_token)))
    end
  end

  describe "someone with an account, signed out" do
    it "still joins from an older copy of the page with the right password" do
      user = create(:user, email_address: "dana@example.com", password: password)
      create(:person, email: "dana@example.com", user: user)

      post do_join_organization_path(organization.invite_token), params: { email: "dana@example.com", password: password }

      expect(response).to redirect_to(my_dashboard_path)
      expect(user.reload.person.organizations).to include(organization)
    end
  end

  describe "an existing signed-in user" do
    it "joins and gets the same greeting" do
      complete_signup("member@example.com")

      post do_join_organization_path(organization.invite_token)

      expect(response).to redirect_to(my_dashboard_path)
      follow_redirect!
      expect(response.body).to include("You&#39;ve joined Big Tent Collective")
    end
  end
end
