# frozen_string_literal: true

require "rails_helper"

# The impersonation notice used to live inside the mobile hamburger panel and
# at the bottom of the desktop sidebar, so you could browse for a long time
# with no reminder of whose account you were in. It is now one global amber bar
# fixed to the top of every page.
RSpec.describe "Impersonation bar", type: :request do
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }
  let(:target) { create(:user, password: "Password123!") }

  def sign_in_superadmin
    post handle_signin_path, params: { email_address: superadmin.email_address, password: "Password123!" }
  end

  context "while impersonating" do
    before do
      sign_in_superadmin
      post impersonate_user_path, params: { email: target.email_address }
      get my_dashboard_path
    end

    it "renders the bar and marks the body so the page makes room for it" do
      expect(response.body).to include('id="impersonation-bar"')
      expect(response.body).to match(/<body[^>]*class="[^"]*\bimpersonating\b/)
    end

    it "renders exactly one impersonation notice — the bar, not a copy in the nav too" do
      expect(response.body.scan('id="impersonation-bar"').size).to eq(1)
      expect(response.body.scan("Impersonating").size).to eq(1)
    end

    it "offsets every piece of chrome pinned to the top of the viewport" do
      # Each of these would otherwise sit underneath the bar. The offset itself
      # is a `body.impersonating .app-top-chrome` rule in the stylesheet.
      expect(response.body.scan("app-top-chrome").size).to eq(3) # sidebar, mobile nav, its panel
    end
  end

  context "when not impersonating" do
    before do
      sign_in_superadmin
      get my_dashboard_path
    end

    it "renders no bar and leaves the body class alone" do
      expect(response.body).not_to include('id="impersonation-bar"')
      expect(response.body).not_to match(/<body[^>]*class="[^"]*\bimpersonating\b/)
    end
  end

  context "signed out with a stale impersonation cookie" do
    it "renders the signin page without a bar instead of crashing" do
      sign_in_superadmin
      post impersonate_user_path, params: { email: target.email_address }
      get signout_path

      # The impersonator cookie can outlive the login; the signed-out signin
      # page must not try to render the bar for a nil Current.user.
      get signin_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('id="impersonation-bar"')
    end
  end

  context "on a mics page, which renders its own richer banner" do
    before do
      sign_in_superadmin
      post impersonate_user_path, params: { email: target.email_address }
      get mics_home_path
    end

    it "does not stack the global bar on top of the mics one" do
      expect(response.body).not_to include('id="impersonation-bar"')
      expect(response.body).to include("Stop impersonating")
    end
  end
end
