# frozen_string_literal: true

require "rails_helper"

# The sign-in screen's steps (AuthController; the sign-in plan, 2026-11-22):
# one screen that starts with the email address. Someone who chose a password
# enters it or uses a code; someone who never chose one gets a code; a new
# address confirms itself with a code and then enters a name. Every step
# lives at exactly /signin.
RSpec.describe "Sign-in steps", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "Password123!" }

  def start(email, **extra)
    post handle_signin_path, params: { step: "start", email_address: email }.merge(extra)
  end

  describe "someone who chose a password" do
    let!(:user) { create(:user, email_address: "maya@example.com", password: password) }

    it "signs in with it, and the device remembers how" do
      start("Maya@Example.com ")
      expect(response).to redirect_to(signin_path)

      post handle_signin_path, params: { step: "password", password: password }
      expect(response).to redirect_to(my_dashboard_path)
      expect(user.sessions.last.sign_in_method).to eq("password")
      expect(user.person).to be_present
    end

    it "signs in with one submit when a password manager filled both fields" do
      start(user.email_address, password: password)
      expect(response).to redirect_to(my_dashboard_path)
    end

    it "is not told a password was wrong when a password manager filled a stale one" do
      start(user.email_address, password: "stale-password")
      expect(response).to redirect_to(signin_path)
      follow_redirect!
      expect(response.body).to include("Enter your password")
      expect(response.body).not_to include("match. Try again")
    end

    it "still signs in from an older page that posts email and password together" do
      post handle_signin_path, params: { email_address: user.email_address, password: password }
      expect(response).to redirect_to(my_dashboard_path)

      delete_session_cookie
      post handle_signin_path, params: { email_address: user.email_address, password: "nope" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That password doesn&#39;t match")
    end

    it "can use a code instead, which proves the address and keeps the password" do
      start(user.email_address)
      post handle_signin_path, params: { step: "send_code" }
      expect(response).to redirect_to(signin_path)

      post handle_signin_path, params: { step: "code", code: emailed_code_for(user.email_address) }
      expect(response).to redirect_to(my_dashboard_path)
      expect(user.reload.email_verified_at).to be_present
      expect(user.authenticate(password)).to be_truthy
      expect(user.sessions.last.sign_in_method).to eq("code")
    end

    it "can start over with another address" do
      start(user.email_address)
      get signin_path(start_over: 1)
      expect(response.body).to include("Sign in or create an account")
      expect(response.body).not_to include("Enter your password")
    end
  end

  describe "someone an organization added, who never chose a password" do
    let!(:user) { User.create_unclaimed!(email_address: "added@example.com") }
    let!(:person) { create(:person, email: "added@example.com", name: "Added Person", user: user) }

    it "gets in with a code and no password" do
      start(user.email_address)
      follow_redirect!
      expect(response.body).to include("Enter your code")

      post handle_signin_path, params: { step: "code", code: emailed_code_for(user.email_address) }
      expect(response).to redirect_to(my_dashboard_path)
      expect(user.reload.email_verified_at).to be_present
      expect(user.claimed?).to be(true)
    end

    it "returns to the page they were trying to reach" do
      get my_tasks_path
      start(user.email_address)
      post handle_signin_path, params: { step: "code", code: emailed_code_for(user.email_address) }
      expect(response.headers["Location"]).to include(my_tasks_path)
    end

    it "whose account was wrongly marked can still use the password they did choose" do
      user.update!(password: password)
      user.update_column(:password_set_at, nil)

      start(user.email_address)
      follow_redirect!
      expect(response.body).to include("Enter your code", "Use your password instead")

      get signin_path(use: "password")
      expect(response.body).to include("Enter your password")
      post handle_signin_path, params: { step: "password", password: password }
      expect(response).to redirect_to(my_dashboard_path)
      expect(user.reload.password_set_at).to be_present
    end
  end

  describe "a new person" do
    it "confirms the address with a code, enters a name, and has an account with no password" do
      expect { complete_signup("New@Example.com", first_name: "Maya", last_name: "Okafor") }.to change(User, :count).by(1)

      expect(response).to redirect_to(my_dashboard_path)
      user = User.find_by!(email_address: "new@example.com")
      expect(user.password_chosen?).to be(false)
      expect(user.email_verified_at).to be_present
      expect(user.person.name).to eq("Maya Okafor")
      expect(user.sessions.last.sign_in_method).to eq("code")
    end

    it "claims the person an organization had already added under that address" do
      added = create(:person, email: "invited@example.com", name: "Invited Person", user: nil)

      complete_signup("invited@example.com")

      expect(added.reload.user).to eq(User.find_by!(email_address: "invited@example.com"))
    end

    it "needs both names" do
      post handle_signin_path, params: signup_params(email_address: "new@example.com")
      post handle_signin_path, params: { step: "code", code: emailed_code_for("new@example.com") }

      expect {
        post handle_signin_path, params: { step: "create", first_name: "Maya", last_name: " " }
      }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Enter your first and last name.")
    end

    it "cannot skip the code" do
      post handle_signin_path, params: signup_params(email_address: "new@example.com")

      expect {
        post handle_signin_path, params: { step: "create", first_name: "Maya", last_name: "Okafor" }
      }.not_to change(User, :count)
      expect(response).to redirect_to(signin_path)
    end

    it "starts over when the confirmed address has waited too long for its name" do
      post handle_signin_path, params: signup_params(email_address: "new@example.com")
      post handle_signin_path, params: { step: "code", code: emailed_code_for("new@example.com") }

      travel(AuthController::CONFIRMED_ADDRESS_LASTS + 1.minute) do
        expect {
          post handle_signin_path, params: { step: "create", first_name: "Maya", last_name: "Okafor" }
        }.not_to change(User, :count)
      end
    end
  end

  describe "codes" do
    let!(:user) { User.create_unclaimed!(email_address: "added@example.com") }

    it "explains a wrong code, and locks the code after five wrong tries" do
      start(user.email_address)
      code = emailed_code_for(user.email_address)
      wrong = code == "000000" ? "111111" : "000000"

      post handle_signin_path, params: { step: "code", code: wrong }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That code doesn&#39;t match")

      4.times { post handle_signin_path, params: { step: "code", code: wrong } }
      expect(response.body).to include("too many tries")

      post handle_signin_path, params: { step: "code", code: code }
      expect(response).to have_http_status(:unprocessable_content)
      expect(cookies[:session_id]).to be_blank
    end

    it "explains an expired code" do
      start(user.email_address)
      code = emailed_code_for(user.email_address)

      travel(SignInCode::LIFETIME + 1.minute) do
        post handle_signin_path, params: { step: "code", code: code }
        expect(response.body).to include("expired or was already used")
      end
    end

    it "does not send a second code straight away, and says a code is already on its way" do
      start(user.email_address)
      expect { post handle_signin_path, params: { step: "send_code" } }.not_to change(SignInCode, :count)
      follow_redirect!
      expect(response.body).to include("We sent a code to this address a moment ago")
    end
  end

  it "says so when what was entered is not an email address" do
    start("not-an-email")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("That doesn&#39;t look like an email address")
  end

  it "takes someone already signed in straight to where they were going" do
    user = create(:user, password: password)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    get signin_path
    expect(response).to redirect_to(my_dashboard_path)
  end

  # Until the Account page has its Sign-in methods section, its "Reset
  # password" button keeps working for a signed-in person as it always has.
  it "still emails a signed-in person a link to choose a new password" do
    user = create(:user, password: password)
    post handle_signin_path, params: { email_address: user.email_address, password: password }

    get password_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reset your password", user.email_address)

    expect {
      post handle_password_path, params: { email_address: user.email_address }
    }.to have_enqueued_mail(AuthMailer, :password)
    expect(response).to redirect_to(account_path)
  end

  def delete_session_cookie
    get signout_path
  end
end
