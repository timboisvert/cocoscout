# frozen_string_literal: true

require "rails_helper"

# Every way of becoming authenticated (signup, signin, password reset) funnels
# through one landing helper. These specs pin its precedence: a stashed return
# path (tokened flow, interrupted deep link) always beats the dashboard
# default, and the default for a brand-new user is the talent dashboard.
RSpec.describe "Post-authentication landing", type: :request do
  let(:password) { "Password123!" }

  describe "signup" do
    it "lands a brand-new signup on the talent dashboard" do
      post handle_signup_path, params: { user: { email_address: "new@example.com", password: password } }

      expect(response).to redirect_to(my_dashboard_path)
    end

    it "returns to an auth-walled page the visitor was trying to reach" do
      get my_tasks_path
      expect(response).to redirect_to(signin_path)

      post handle_signup_path, params: { user: { email_address: "walled@example.com", password: password } }

      expect(response.headers["Location"]).to include(my_tasks_path)
    end
  end

  describe "signin" do
    it "honors a redirect_to param stashed by the signin page" do
      user = create(:user)
      Person.create!(email: user.email_address, name: "Someone", user: user)

      get signin_path(redirect_to: my_tasks_path)
      post handle_signin_path, params: { email_address: user.email_address, password: user.password }

      expect(response).to redirect_to(my_tasks_path)
    end

    it "sends a returning manager back to the production dashboard" do
      user = create(:user)
      person = Person.create!(email: user.email_address, name: "Someone", user: user)
      org = Organization.create!(name: "Landing Org", owner: user)
      OrganizationRole.create!(user: user, organization: org, company_role: "manager")
      org.people << person
      user.update!(welcomed_production_at: Time.current)

      post handle_signin_path, params: { email_address: user.email_address, password: user.password }
      get manage_path # stamps the last_dashboard cookie with "manage"
      delete signout_path

      post handle_signin_path, params: { email_address: user.email_address, password: user.password }

      expect(response).to redirect_to(manage_path)
    end
  end

  describe "password reset" do
    it "signs the user in directly instead of bouncing to the signin form" do
      user = create(:user)
      token = user.generate_token_for(:password_reset)

      post handle_reset_path(token), params: { password: "NewPassword456!" }

      expect(response).to redirect_to(my_dashboard_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "honors a stashed return path (activation from a deep link)" do
      user = create(:user)
      token = user.generate_token_for(:password_reset)

      get my_tasks_path # logged out — stashes the return path
      post handle_reset_path(token), params: { password: "NewPassword456!" }

      expect(response.headers["Location"]).to include(my_tasks_path)
    end
  end
end
