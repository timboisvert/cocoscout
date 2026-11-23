# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

# Passkeys (sign-in plan phase 4): made from the Account page or the apps by
# someone signed in, and signing in on the website's /signin and the apps'
# own screens. WebAuthn::FakeClient plays the browser and its authenticator.
RSpec.describe "Passkeys", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let!(:user) { create(:user, email_address: "maya@example.com", password: password) }
  let(:origin) { "http://www.example.com" }
  let(:client) { WebAuthn::FakeClient.new(origin) }
  let(:app_agent) { "CocoScout/1.3 (11; nav 2) CocoMenu/bar CocoAuth/1 Hotwire Native iOS" }

  before { create(:person, user: user, email: user.email_address, name: "Maya Lin") }

  def sign_in
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def json_post(path, body, headers = {})
    post path, params: body.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(headers)
    response.parsed_body
  end

  def add_passkey(with: client)
    options = json_post(passkey_options_account_path, {})
    json_post(passkeys_account_path, { credential: with.create(challenge: options["challenge"], user_verified: true) })
  end

  describe "adding one on the Account page" do
    it "keeps the passkey, names it, and tells the person by email and notification" do
      sign_in
      options = json_post(passkey_options_account_path, {})
      expect(options["rp"]["id"]).to eq("www.example.com")
      expect(options["user"]["name"]).to eq("maya@example.com")
      expect(options["user"]["id"]).to eq(user.reload.webauthn_id)
      expect(options["authenticatorSelection"]).to include("residentKey" => "required", "userVerification" => "required")

      answer = json_post(passkeys_account_path, { credential: client.create(challenge: options["challenge"], user_verified: true) })
      expect(answer["status"]).to eq("added")
      passkey = user.passkeys.sole
      expect(passkey.name).to eq("Made on a device")
      expect(passkey.transports).to eq(%w[internal])
      expect(Notification.where(user: user, kind: "auth_passkey_added").sole.title).to eq("A passkey now signs you in to CocoScout.")
      perform_enqueued_jobs
      expect(ActionMailer::Base.deliveries.last.subject).to eq("A passkey now signs you in to CocoScout")
    end

    it "excludes the passkeys the account already has, and takes each challenge once" do
      sign_in
      options = json_post(passkey_options_account_path, {})
      made = client.create(challenge: options["challenge"], user_verified: true)
      json_post(passkeys_account_path, { credential: made })
      expect(json_post(passkeys_account_path, { credential: made })["status"]).to eq("error")
      expect(user.passkeys.count).to eq(1)

      expect(json_post(passkey_options_account_path, {})["excludeCredentials"].map { |c| c["id"] }).to eq([ user.passkeys.sole.external_id ])
    end

    it "refuses a passkey made without the face, fingerprint, or screen lock" do
      sign_in
      options = json_post(passkey_options_account_path, {})
      expect(json_post(passkeys_account_path, { credential: client.create(challenge: options["challenge"], user_verified: false) })["status"]).to eq("error")
      expect(user.passkeys).to be_empty
    end

    it "removes one" do
      sign_in
      add_passkey
      delete passkey_account_path(user.passkeys.sole)
      expect(response).to redirect_to(account_path)
      expect(user.passkeys.reload).to be_empty
    end

    it "shows them on the Account page" do
      sign_in
      add_passkey
      get account_path
      expect(response.body).to include("Made on a device")
      expect(response.body).to include("Add a passkey")
    end
  end

  describe "signing in with one on the website" do
    it "starts the session and names where to land" do
      sign_in
      add_passkey
      reset!

      get sign_in_passkey_options_path, headers: { "Accept" => "application/json" }
      options = response.parsed_body
      expect(options["userVerification"]).to eq("required")
      expect(options["allowCredentials"]).to be_blank

      answer = json_post(sign_in_passkey_path, { credential: client.get(challenge: options["challenge"], user_verified: true) })
      expect(answer["status"]).to eq("signed_in")
      expect(answer["landing"]).to be_present
      expect(user.sessions.last.sign_in_method).to eq("passkey")
      expect(user.passkeys.sole.last_used_at).to be_present
      get account_path
      expect(response).to have_http_status(:ok)
    end

    it "refuses an answer to someone else's challenge, and a passkey it doesn't know" do
      sign_in
      add_passkey
      reset!

      expect(json_post(sign_in_passkey_path, { credential: client.get(challenge: SecureRandom.urlsafe_base64(32), user_verified: true) })["status"]).to eq("error")

      get sign_in_passkey_options_path, headers: { "Accept" => "application/json" }
      stranger = WebAuthn::FakeClient.new(origin)
      stranger.create(challenge: response.parsed_body["challenge"], user_verified: true)
      answer = json_post(sign_in_passkey_path, { credential: stranger.get(challenge: response.parsed_body["challenge"], user_verified: true) })
      expect(answer["status"]).to eq("error")
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "in the apps" do
    let(:app_headers) { { "User-Agent" => app_agent } }

    it "makes a passkey for the signed-in account, from a build that has its own sign-in screens" do
      json_post(app_sign_in_identify_path, { email: user.email_address, password: password }, app_headers)
      get app_passkey_options_path, headers: app_headers.merge("Accept" => "application/json")
      options = response.parsed_body
      expect(options["user"]["name"]).to eq("maya@example.com")

      answer = json_post(app_passkeys_path, { credential: client.create(challenge: options["challenge"], user_verified: true) }, app_headers)
      expect(answer).to include("status" => "added")
      expect(user.passkeys.count).to eq(1)

      get app_passkey_options_path, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end

    it "signs in with one and tells the phone how, for Welcome back" do
      sign_in
      add_passkey
      reset!

      get app_sign_in_passkey_options_path, headers: app_headers.merge("Accept" => "application/json")
      challenge = response.parsed_body["challenge"]
      answer = json_post(app_sign_in_passkey_path, { credential: client.get(challenge: challenge, user_verified: true) }, app_headers)
      expect(answer).to include("status" => "signed_in", "method" => "passkey", "email" => "maya@example.com", "first_name" => "Maya")
      expect(user.sessions.last.sign_in_method).to eq("passkey")
    end

    it "takes a passkey signed by the Android app, whose origin is its signing certificate" do
      android = WebAuthn::FakeClient.new(SignIn::Passkeys.android_origins.first)
      sign_in
      options = json_post(passkey_options_account_path, {})
      answer = json_post(passkeys_account_path, { credential: android.create(challenge: options["challenge"], rp_id: "www.example.com", user_verified: true) })
      expect(answer["status"]).to eq("added")
      reset!

      get app_sign_in_passkey_options_path, headers: app_headers.merge("Accept" => "application/json")
      challenge = response.parsed_body["challenge"]
      answer = json_post(app_sign_in_passkey_path, { credential: android.get(challenge: challenge, rp_id: "www.example.com", user_verified: true) }, app_headers)
      expect(answer["status"]).to eq("signed_in")
    end
  end
end
