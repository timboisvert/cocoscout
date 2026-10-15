# frozen_string_literal: true

require "rails_helper"

# The sign-in pages share one single-column shell (shared/auth/_shell): a
# lede that says what the account is for, one form, and copy that quotes the
# model rather than a number that can drift. Every page that creates an
# account carries the bot-defense token, including the ones that embed the
# form (sign-up and audition entry, course registration).
RSpec.describe "Auth shell", type: :request do
  let(:password) { "Password123!" }

  describe "sign in" do
    it "says what's on the other side and points invited people at choosing a password" do
      get signin_path
      expect(response.body).to include("Everything about your shows lives here")
      expect(response.body).not_to include("Welcome back")
      expect(response.body).to include("Invited by an organization?", password_path, "Create an account")
      expect(response.body).to include("cocoscout.com")
    end

    it "in the app shows the pocket lede and a Back link to the welcome screen" do
      get signin_path, headers: { "User-Agent" => "CocoScout Turbo Native iOS" }
      expect(response.body).to include("in your pocket", welcome_path)
    end

    it "tells someone who signed up with an existing email to sign in, with a path to a first password" do
      user = create(:user, password: password)
      token = SignupFormToken.generate
      travel(SignupFormToken::MIN_AGE + 1.second) do
        post handle_signup_path, params: { user: { email_address: user.email_address, password: password }, signup_token: token }
      end
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("You already have an account.", user.email_address, "choose one now")
    end

    it "explains a wrong password without a red box" do
      user = create(:user, password: password)
      post handle_signin_path, params: { email_address: user.email_address, password: "nope" }
      expect(response.body).to include("That email and password don't match", "reset your password")
      expect(response.body).not_to include("bg-red-")
    end
  end

  describe "create account" do
    it "carries the form token and honeypot, the free pill and the lede" do
      get signup_path
      expect(response.body).to include("Free to join · No card needed", "One account for everything you do in live entertainment")
      expect(response.body).to include('name="signup_token"', 'name="website"')
      expect(response.body).to include("By creating an account")
    end
  end

  describe "forgot and reset" do
    it "quotes the link's real lifetime and covers people who never set a password" do
      get password_path
      expect(response.body).to include("never set one because an organization created your account", "The link works for 2 hours")
    end

    it "after sending, the sign-in page shows a plain notice, not a green box" do
      user = create(:user, password: password)
      post handle_password_path, params: { email_address: user.email_address }
      follow_redirect!
      expect(response.body).to include("Check your email.", "It works for 2 hours", "Send the link again")
      expect(response.body).not_to include("bg-green-")
    end

    it "the reset page is about choosing a password, and shows whose account it is" do
      user = create(:user, password: password)
      get reset_path(token: user.generate_token_for(:password_reset))
      expect(response.body).to include("Choose your password", user.email_address, "Set password and sign in")
      expect(response.body).not_to include("Then you")
    end

    it "an expired link lands on the forgot page with the reason" do
      get reset_path(token: "stale")
      follow_redirect!
      expect(response.body).to include("That link has expired.", "Email me a new link")
    end
  end

  describe "invitation pages" do
    let(:org) { create(:organization, name: "Blue Room Theater") }

    it "the organization join link explains what the account is for and carries the strip" do
      org.update_column(:invite_token, "join-token-9")
      get join_organization_path("join-token-9")
      expect(response.body).to include("invited you to join them on CocoScout", "Create your account to join",
                                       "Join Blue Room Theater", "Free to join · No card needed", "Sign in to join")
    end

    it "a personal invitation is about choosing a password, with the email locked" do
      invitation = create(:person_invitation, organization: org, email: "maya@example.com")
      get manage_accept_person_invitations_path(token: invitation.token)
      expect(response.body).to include("Choose your password", "maya@example.com", "set up your CocoScout account",
                                       "Join Blue Room Theater", "Decline this invitation", "Already set a password?")
    end

    it "a team invitation for a new person chooses a password; for an existing one it signs in" do
      invitation = create(:team_invitation, organization: org, email: "new@example.com")
      get accept_manage_team_invitations_path(token: invitation.token)
      expect(response.body).to include("Choose your password", "invited you to their team", "Join Blue Room Theater")

      create(:user, email_address: "old@example.com", password: password)
      invitation = create(:team_invitation, organization: org, email: "old@example.com")
      get accept_manage_team_invitations_path(token: invitation.token)
      expect(response.body).to include("Sign in to join the team", "Forgot your password?")
      expect(response.body).not_to include("data-password-strength-target=\"meter\"")
    end

    it "a group invitation names the group and the inviter" do
      invitation = create(:group_invitation, email: "maya@example.com")
      get accept_group_invitation_path(invitation.token)
      expect(response.body).to include("Choose your password", invitation.group.name, "maya@example.com", "Join #{invitation.group.name}")
    end
  end

  describe "embedded account forms" do
    it "course registration carries the bot-defense token so the form actually goes through" do
      org = create(:organization)
      production = create(:production, organization: org)
      offering = create(:course_offering, production: production, price_cents: 10_000, capacity: 12)
      create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: 1.month.from_now, duration_minutes: 120)
      get my_course_entry_path(code: offering.short_code)
      follow_redirect! while response.redirect?
      expect(response.body).to include('name="signup_token"', 'name="website"', "Create account and continue")
    end
  end
end
