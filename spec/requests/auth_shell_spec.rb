# frozen_string_literal: true

require "rails_helper"

# The sign-in pages share one single-column shell (shared/auth/_shell): a
# lede that says what the account is for, one form, and copy that quotes the
# model rather than a number that can drift. Every page that creates an
# email address carries the bot-defense token, including the ones that embed
# the form (sign-up and audition entry, course registration).
RSpec.describe "Auth shell", type: :request do
  let(:password) { "Password123!" }

  describe "the first step" do
    it "is one screen for signing in and creating an account, with the bot defenses" do
      get signin_path
      expect(response.body).to include("Sign in or create an account", "Everything about your shows lives here")
      expect(response.body).not_to include("Welcome back", "Invited by an organization?")
      expect(response.body).to include('name="signup_token"', 'name="website"', "cocoscout.com", "By continuing")
    end

    it "in the app shows the pocket lede and a Back link to the welcome screen" do
      get signin_path, headers: { "User-Agent" => "CocoScout Turbo Native iOS" }
      expect(response.body).to include("the door scanner", welcome_path)
    end

    it "is where the old sign-up and forgot-password addresses lead" do
      get signup_path(email_address: "maya@example.com")
      expect(response).to redirect_to(signin_path(email_address: "maya@example.com"))
      get password_path
      expect(response).to redirect_to(signin_path)
    end
  end

  describe "the next step" do
    it "requests the password from someone who chose one, with a code as the other way in" do
      user = create(:user, password: password)
      post handle_signin_path, params: { step: "start", email_address: user.email_address }
      follow_redirect!
      expect(response.body).to include("Enter your password", user.email_address, "Email me a code instead", "Change")
    end

    it "explains a wrong password without a red box" do
      user = create(:user, password: password)
      post handle_signin_path, params: { step: "start", email_address: user.email_address }
      post handle_signin_path, params: { step: "password", password: "nope" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That password doesn&#39;t match", "use a code instead")
      expect(response.body).not_to include("bg-red-")
    end

    it "sends a code to someone who never chose a password, and quotes the code's real lifetime" do
      user = User.create_unclaimed!(email_address: "added@example.com")
      post handle_signin_path, params: { step: "start", email_address: user.email_address }
      follow_redirect!
      expect(response.body).to include("Enter your code", "added@example.com", "It works for 10 minutes", "Send a new code")
      expect(response.body).not_to include("bg-green-")
      expect(emailed_code_for("added@example.com")).to match(/\A\d{6}\z/)
    end

    it "sends a code from an old forgot-password page" do
      user = create(:user, password: password)
      post handle_password_path, params: { email_address: user.email_address }
      follow_redirect!
      expect(response.body).to include("Enter your code", user.email_address)
    end

    it "requests a new person's name once the code has confirmed their address" do
      post handle_signin_path, params: signup_params(email_address: "new@example.com")
      post handle_signin_path, params: { step: "code", code: emailed_code_for("new@example.com") }
      follow_redirect!
      expect(response.body).to include("Create your account", "Free to join · No card needed", "First name", "Last name",
                                       "By creating an account")
      expect(response.body).not_to include('type="password"')
    end
  end

  describe "reset links already in inboxes" do
    it "the reset page is about choosing a password, and shows whose account it is" do
      user = create(:user, password: password)
      get reset_path(token: user.generate_token_for(:password_reset))
      expect(response.body).to include("Choose your password", user.email_address, "Set password and sign in")
      expect(response.body).not_to include("Then you")
    end

    it "an expired link lands on the first step with the reason and a code as the way in" do
      get reset_path(token: "stale")
      follow_redirect!
      expect(response.body).to include("That link has expired.", "send you a code instead")
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
      expect(response.body).to include('name="signup_token"', 'name="website"', "Sign in or create an account to register")
    end
  end
end
