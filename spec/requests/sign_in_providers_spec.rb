# frozen_string_literal: true

require "rails_helper"

# Continue with Apple and Continue with Google on the website (sign-in plan
# phase 2; Tim, 2026-11-22). The providers' own pages and token checks are
# stubbed; what's tested is what each answer does here.
RSpec.describe "Signing in with Apple and Google", type: :request do
  include ActiveJob::TestHelper

  let(:claims) { { "sub" => "g-1", "email" => "maya@example.com", "email_verified" => true, "given_name" => "Maya", "family_name" => "Lin" } }
  let(:live) { "on" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    { "SIGN_IN_WITH_PROVIDERS" => live, "GOOGLE_SIGNIN_CLIENT_ID" => "google-client", "GOOGLE_SIGNIN_CLIENT_SECRET" => "secret",
      "APPLE_TEAM_ID" => "TEAM", "APPLE_SERVICES_ID" => "com.cocoscout.web", "APPLE_KEY_ID" => "KEY",
      "APPLE_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").private_to_pem }.each do |name, value|
      allow(ENV).to receive(:[]).with(name).and_return(value)
    end
    allow(SignIn::OAuth).to receive(:exchange).and_return({ id_token: "token", refresh_token: "refresh-1" })
    allow(SignIn::IdToken).to receive(:verify) { claims }
    allow(SignIn::OAuth).to receive(:revoke_apple).and_return(true)
    # Apple's return is parked in the cache for its second hop.
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  # Leaves for Google, comes back with the state it was given.
  def sign_in_with(provider = "google")
    post sign_in_provider_path(provider)
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]
    if provider == "apple"
      post apple_sign_in_callback_path, params: { code: "c", state: state, user: { name: { firstName: "Ana", lastName: "Ruiz" } }.to_json }
      follow_redirect!
    else
      get google_sign_in_callback_path(code: "c", state: state)
    end
  end

  it "shows the buttons on the first screen when they're on, Apple first on a Mac, and none in the app" do
    get signin_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)" }
    expect(response.body).to include("Continue with Apple", "Continue with Google")
    expect(response.body.index("Continue with Apple")).to be < response.body.index("Continue with Google")
    # Email is the main way in; Apple and Google sit below it (Tim, 2026-11-22).
    expect(response.body.index('name="email_address"')).to be < response.body.index("Continue with Apple")

    get signin_path, headers: { "User-Agent" => "Mozilla/5.0 (iPhone) Turbo Native iOS" }
    expect(response.body).not_to include("Continue with Google")
  end

  context "while the switch is off" do
    let(:live) { nil }

    it "shows them only in a browser a superadmin has used" do
      get signin_path
      expect(response.body).not_to include("Continue with Google")

      admin = create(:user, email_address: User::SUPERADMIN_EMAILS.first, password: "Password123!")
      post handle_signin_path, params: { email_address: admin.email_address, password: "Password123!" }
      get account_path
      expect(response.body).to include('data-sign-in-method="google"')
      get signout_path
      get signin_path
      expect(response.body).to include("Continue with Google")
    end
  end

  it "makes a new account with the name Google gave, connected, and signs in" do
    sign_in_with
    expect(response).to redirect_to(sign_in_provider_continue_path)
    follow_redirect!
    expect(response.body).to include("Create your account", 'value="Maya"', 'value="Lin"', "maya@example.com")

    post sign_in_provider_continue_path, params: { step: "create", first_name: "Maya", last_name: "Lin" }
    user = User.find_by!(email_address: "maya@example.com")
    expect(user.user_identities.sole).to have_attributes(provider: "google", uid: "g-1")
    expect(user.email_verified_at).to be_present
    expect(user.sessions.last.sign_in_method).to eq("google")
    expect(Notification.where(user: user, kind: "auth_method_connected")).to be_empty # the welcome email goes instead
  end

  it "signs in a connected account in one step" do
    user = create(:user)
    user.user_identities.create!(provider: "google", uid: "g-1")
    sign_in_with
    expect(response.location).not_to include("/auth/continue")
    expect(user.sessions.last.sign_in_method).to eq("google")
  end

  it "connects an account with a chosen password once that password is entered, and keeps it" do
    user = create(:user, email_address: "maya@example.com", password: "Password123!")
    sign_in_with
    follow_redirect!
    expect(response.body).to include("Connect your Google account", "Email me a code instead")

    post sign_in_provider_continue_path, params: { step: "password", password: "wrong" }
    expect(response.body).to include("That password doesn&#39;t match")
    post sign_in_provider_continue_path, params: { step: "password", password: "Password123!" }
    expect(user.reload.user_identities.sole.provider).to eq("google")
    expect(user.authenticate("Password123!")).to be_truthy
    expect(Notification.where(user: user, kind: "auth_method_connected").sole.title).to eq("Google now signs you in to CocoScout.")
  end

  it "connects with a code instead, replacing the password" do
    user = create(:user, email_address: "maya@example.com", password: "Password123!")
    sign_in_with
    post sign_in_provider_continue_path, params: { step: "send_code" }
    follow_redirect!
    expect(response.body).to include("Enter your code")

    post sign_in_provider_continue_path, params: { step: "code", code: emailed_code_for("maya@example.com") }
    expect(user.reload.user_identities.sole.provider).to eq("google")
    expect(user.authenticate("Password123!")).to be(false)
  end

  it "never connects a superadmin with a code" do
    create(:user, email_address: User::SUPERADMIN_EMAILS.first, password: "Password123!")
    claims["email"] = User::SUPERADMIN_EMAILS.first
    sign_in_with
    follow_redirect!
    expect(response.body).to include("Connect your Google account")
    expect(response.body).not_to include("Email me a code instead")
  end

  it "asks Hide My Email for the real address, proves it with a code, and finds the account there" do
    claims.merge!("email" => "abc@privaterelay.appleid.com", "is_private_email" => "true")
    user = create(:user, email_address: "ana@example.com", password: "Password123!")
    sign_in_with("apple")
    expect(response).to redirect_to(sign_in_provider_continue_path)
    follow_redirect!
    expect(response.body).to include("Add your email address")

    post sign_in_provider_continue_path, params: { step: "email", email_address: "ana@example.com" }
    post sign_in_provider_continue_path, params: { step: "code", code: emailed_code_for("ana@example.com") }
    identity = user.reload.user_identities.sole
    expect(identity).to have_attributes(provider: "apple", private_email: true, refresh_token: "refresh-1")
    expect(User.where(email_address: "abc@privaterelay.appleid.com")).to be_empty
  end

  it "connects from the Account page, and disconnects, revoking Apple" do
    user = create(:user, password: "Password123!")
    post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
    claims["email"] = "different@example.com"
    sign_in_with("apple")
    expect(response).to redirect_to(account_path)
    expect(user.reload.user_identities.sole).to have_attributes(provider: "apple", email: "different@example.com")

    delete disconnect_sign_in_provider_path("apple")
    expect(user.user_identities.reload).to be_empty
    expect(SignIn::OAuth).to have_received(:revoke_apple).with("refresh-1", client_id: "com.cocoscout.web")
  end

  it "refuses a return that doesn't carry this browser's state" do
    post sign_in_provider_path("google")
    get google_sign_in_callback_path(code: "c", state: "forged")
    expect(response).to redirect_to(signin_path)
    expect(SignIn::OAuth).not_to have_received(:exchange)
  end

  it "drops a connection when Apple says the person withdrew it" do
    user = create(:user)
    user.user_identities.create!(provider: "apple", uid: "a-9", refresh_token: "r")
    allow(SignIn::IdToken).to receive(:verify).and_return({ "events" => { type: "consent-revoked", sub: "a-9" }.to_json })
    post apple_sign_in_notifications_path, params: { payload: "jwt" }
    expect(response).to have_http_status(:ok)
    expect(user.user_identities.reload).to be_empty
    expect(SignIn::OAuth).not_to have_received(:revoke_apple)
  end
end
