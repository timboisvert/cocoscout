# frozen_string_literal: true

require "rails_helper"

# The Account page's Sign-in methods (the sign-in plan, 2026-11-22): choosing
# or changing the password, and changing the sign-in email. Being signed in
# isn't enough for either: a password change takes the current password or a
# code sent to the account's email, and a new email address takes a code sent
# to that address.
RSpec.describe "Account sign-in methods", type: :request do
  let(:password) { "Password123!" }
  let(:new_password) { "Brand-New-456!" }

  def sign_in_with_password(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def sign_in_with_code(user)
    post handle_signin_path, params: { step: "start", email_address: user.email_address }
    post handle_signin_path, params: { step: "code", code: emailed_code_for(user.email_address) }
  end

  describe "the Account page" do
    it "lists the emailed code and a chosen password, with a way to change it" do
      user = create(:user, password: password)
      sign_in_with_password(user)

      get account_path
      expect(response.body).to include("Sign-in methods", "Email code", "Always available", "Chosen on", choose_password_account_path)
      expect(response.body).not_to include("Reset password")
    end

    it "says when no password has been chosen" do
      user = User.create_unclaimed!(email_address: "added@example.com")
      create(:person, email: user.email_address, user: user)
      sign_in_with_code(user)

      get account_path
      expect(response.body).to include("Not chosen. The code signs you in without one.", "Choose a password")
    end
  end

  describe "changing a password" do
    let!(:user) { create(:user, email_address: "maya@example.com", password: password) }

    before { sign_in_with_password(user) }

    it "takes the current password, and signs out everywhere else" do
      elsewhere = user.sessions.create!(user_agent: "Another browser")

      patch choose_password_account_path, params: { current_password: password, password: new_password }

      expect(response).to redirect_to(account_path)
      expect(user.reload.authenticate(new_password)).to be_truthy
      expect(Session.exists?(elsewhere.id)).to be(false)
      get account_path
      expect(response).to have_http_status(:ok)
    end

    it "refuses a wrong current password" do
      patch choose_password_account_path, params: { current_password: "nope", password: new_password }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That isn&#39;t your current password")
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "takes an emailed code from someone who forgot the current one" do
      post password_code_account_path
      expect(response).to redirect_to(choose_password_account_path(with: "code"))

      patch choose_password_account_path, params: { with: "code", code: emailed_code_for(user.email_address), password: new_password }

      expect(response).to redirect_to(account_path)
      expect(user.reload.authenticate(new_password)).to be_truthy
      expect(user.email_verified_at).to be_present
    end

    it "does not use up the code on a password that breaks the rules" do
      post password_code_account_path
      code = emailed_code_for(user.email_address)

      patch choose_password_account_path, params: { with: "code", code: code, password: "short" }
      expect(response).to have_http_status(:unprocessable_content)

      patch choose_password_account_path, params: { with: "code", code: code, password: new_password }
      expect(response).to redirect_to(account_path)
    end

    it "refuses a wrong code" do
      post password_code_account_path
      code = emailed_code_for(user.email_address)

      patch choose_password_account_path, params: { with: "code", code: (code == "000000" ? "111111" : "000000"), password: new_password }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.authenticate(password)).to be_truthy
    end
  end

  describe "choosing a first password" do
    it "needs a code, because there is no current password to enter" do
      user = User.create_unclaimed!(email_address: "added@example.com")
      create(:person, email: user.email_address, user: user)
      sign_in_with_code(user)

      get choose_password_account_path
      expect(response.body).to include("Choose a password", "A password is optional", "Email me a code")
      expect(response.body).not_to include("Current password")

      patch choose_password_account_path, params: { current_password: "", password: new_password }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.password_chosen?).to be(false)

      post password_code_account_path
      patch choose_password_account_path, params: { code: emailed_code_for(user.email_address), password: new_password }
      expect(response).to redirect_to(account_path)
      expect(user.reload.password_chosen?).to be(true)
    end
  end

  describe "changing the sign-in email" do
    let!(:user) { create(:user, email_address: "old@example.com", password: password) }
    let!(:person) { create(:person, email: "old@example.com", user: user) }
    let(:json) { { "ACCEPT" => "application/json" } }

    before { sign_in_with_password(user) }

    it "changes nothing until the code sent to the new address is entered" do
      patch update_email_account_path, params: { email_address: "New@Example.com" }, headers: json, as: :json
      expect(response.parsed_body).to include("success" => true, "needs_code" => true, "email_address" => "new@example.com")
      expect(user.reload.email_address).to eq("old@example.com")

      patch update_email_account_path,
            params: { email_address: "new@example.com", code: emailed_code_for("new@example.com"), profile_ids: [ person.id ] },
            headers: json, as: :json
      expect(response.parsed_body).to include("success" => true)
      expect(user.reload.email_address).to eq("new@example.com")
      expect(user.email_verified_at).to be_present
      expect(person.reload.email).to eq("new@example.com")
    end

    it "refuses a wrong code and an address that already has an account" do
      patch update_email_account_path, params: { email_address: "new@example.com" }, headers: json, as: :json
      patch update_email_account_path, params: { email_address: "new@example.com", code: "000001" }, headers: json, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.email_address).to eq("old@example.com")

      create(:user, email_address: "taken@example.com")
      patch update_email_account_path, params: { email_address: "taken@example.com" }, headers: json, as: :json
      expect(response.parsed_body["error"]).to include("already exists")
    end
  end
end
