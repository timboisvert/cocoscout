# frozen_string_literal: true

require "rails_helper"

# The apps' own sign-in screens (sign-in plan phase 3; Tim, 2026-11-22): the
# same steps as the website, answered with JSON, starting the web view's
# session (App::SignInController). The providers' token checks are stubbed.
RSpec.describe "The apps' sign-in screens", type: :request do
  include ActiveJob::TestHelper

  let(:app_agent) { "CocoScout/1.3 (11; nav 2) CocoMenu/bar CocoAuth/1 Hotwire Native iOS" }
  let(:claims) { { "sub" => "a-1", "email" => "maya@example.com", "email_verified" => true } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    { "SIGN_IN_WITH_PROVIDERS" => "on", "GOOGLE_SIGNIN_CLIENT_ID" => "google-client", "GOOGLE_SIGNIN_CLIENT_SECRET" => "secret",
      "APPLE_TEAM_ID" => "TEAM", "APPLE_SERVICES_ID" => "com.cocoscout.web", "APPLE_KEY_ID" => "KEY",
      "APPLE_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").private_to_pem }.each do |name, value|
      allow(ENV).to receive(:[]).with(name).and_return(value)
    end
    allow(SignIn::OAuth).to receive(:exchange).and_return({ id_token: "token", refresh_token: "refresh-1" })
    allow(SignIn::IdToken).to receive(:verify) { claims }
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  def app_post(path, body = {})
    post path, params: body.to_json, headers: { "User-Agent" => app_agent, "Content-Type" => "application/json", "Accept" => "application/json" }
    response.parsed_body
  end

  def app_get(path)
    get path, headers: { "User-Agent" => app_agent, "Accept" => "application/json" }
    response.parsed_body
  end

  def sent_code
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    mail.text_part&.body&.decoded.to_s[/\b\d{6}\b/] || mail.body.decoded[/\b\d{6}\b/]
  end

  it "answers only the app's own screens: JSON, from a build that says it has them" do
    post app_sign_in_identify_path, params: { email: "x@example.com" }.to_json, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:not_found)
    post app_sign_in_identify_path, params: { email: "x@example.com" }, headers: { "User-Agent" => app_agent }
    expect(response).to have_http_status(:not_found)
  end

  it "signs a password person in and starts the web view's session" do
    user = create(:user, email_address: "sam@example.com", password: "Password123!", password_set_at: 1.year.ago)

    expect(app_post(app_sign_in_identify_path, email: "Sam@Example.com ")).to include("status" => "step", "step" => "password", "email" => "sam@example.com")
    expect(app_post(app_sign_in_password_path, password: "nope")).to include("status" => "error", "error" => "password")

    body = app_post(app_sign_in_password_path, password: "Password123!")
    expect(body).to include("status" => "signed_in", "email" => "sam@example.com", "method" => "password")
    expect(body["landing"]).to start_with("http://www.example.com/")
    expect(response.headers["Set-Cookie"].to_s).to include("session_id=")
    expect(user.sessions.last.sign_in_method).to eq("password")
  end

  it "takes a password that comes with the address in one go" do
    create(:user, email_address: "sam@example.com", password: "Password123!", password_set_at: 1.year.ago)
    expect(app_post(app_sign_in_identify_path, email: "sam@example.com", password: "Password123!")["status"]).to eq("signed_in")
  end

  it "makes a new account by code and name" do
    expect(app_post(app_sign_in_identify_path, email: "new@example.com")).to include("step" => "code", "code_lifetime" => "10 minutes")
    code = sent_code
    expect(app_post(app_sign_in_code_path, code: "000000")).to include("status" => "error", "error" => "wrong")
    expect(app_post(app_sign_in_code_path, code: code)).to include("step" => "create")
    expect(app_post(app_sign_in_create_path, first_name: "New", last_name: "")).to include("error" => "name")

    body = app_post(app_sign_in_create_path, first_name: "New", last_name: "Person")
    expect(body["status"]).to eq("signed_in")
    user = User.find_by(email_address: "new@example.com")
    expect(user.person.name).to eq("New Person")
    expect(user.email_verified_at).to be_present
  end

  it "sends a code to someone who never chose a password" do
    User.create_unclaimed!(email_address: "added@example.com")

    expect(app_post(app_sign_in_identify_path, email: "added@example.com")["step"]).to eq("code")
    expect(app_post(app_sign_in_code_path, code: sent_code)["status"]).to eq("signed_in")
  end

  it "starts over when the step has lapsed" do
    expect(app_post(app_sign_in_password_path, password: "x")).to include("step" => "start")
  end

  describe "Apple and Google" do
    it "signs in a connected account from the app's own sheet, checking the nonce the session asked for" do
      user = create(:user, email_address: "maya@example.com")
      user.user_identities.create!(provider: "apple", uid: "a-1", email: "maya@example.com")

      expect(app_post(app_sign_in_provider_path, provider: "apple", id_token: "t")).to include("status" => "error")

      nonce = app_get(app_sign_in_nonce_path)["nonce"]
      body = app_post(app_sign_in_provider_path, provider: "apple", id_token: "t", authorization_code: "code-1")
      expect(body["status"]).to eq("signed_in")
      expect(SignIn::IdToken).to have_received(:verify).with("apple", "t", nonce: Digest::SHA256.hexdigest(nonce))
      expect(SignIn::OAuth).to have_received(:exchange).with("apple", code: "code-1", redirect_uri: nil, client_id: "com.cocoscout.app")
    end

    it "answers the nonce with a status, which the iPhone app requires of every answer" do
      expect(app_get(app_sign_in_nonce_path)).to include("status" => "ready", "nonce" => be_present)
    end

    it "checks Google's nonce as given" do
      reply = app_get(app_sign_in_nonce_path)
      expect(reply["google_client_id"]).to eq("google-client")
      nonce = reply["nonce"]
      app_post(app_sign_in_provider_path, provider: "google", id_token: "t")
      expect(SignIn::IdToken).to have_received(:verify).with("google", "t", nonce: nonce)
    end

    it "connects once by password when the address has an account with one" do
      user = create(:user, email_address: "maya@example.com", password: "Password123!", password_set_at: 1.year.ago)
      app_get(app_sign_in_nonce_path)

      expect(app_post(app_sign_in_provider_path, provider: "apple", id_token: "t")).to include("step" => "connect", "provider" => "Apple", "email" => "maya@example.com")
      expect(app_post(app_sign_in_connect_path, password: "nope")["error"]).to eq("password")
      expect(app_post(app_sign_in_connect_path, password: "Password123!")["status"]).to eq("signed_in")
      expect(user.user_identities.sole).to have_attributes(provider: "apple", uid: "a-1", client_id: "com.cocoscout.app")
    end

    it "makes a new account with the provider connected" do
      app_get(app_sign_in_nonce_path)
      expect(app_post(app_sign_in_provider_path, provider: "google", id_token: "t", first_name: "Maya", last_name: "Lin"))
        .to include("step" => "create", "first_name" => "Maya", "last_name" => "Lin")
      expect(app_post(app_sign_in_create_path, first_name: "Maya", last_name: "Lin")["status"]).to eq("signed_in")
      expect(User.find_by(email_address: "maya@example.com").user_identities.sole.provider).to eq("google")
    end

    it "asks Hide My Email for the real address and proves it with a code" do
      claims.merge!("email" => "x@privaterelay.appleid.com", "is_private_email" => true)
      app_get(app_sign_in_nonce_path)
      expect(app_post(app_sign_in_provider_path, provider: "apple", id_token: "t")["step"]).to eq("add_email")
      expect(app_post(app_sign_in_add_email_path, email: "y@privaterelay.appleid.com")["error"]).to eq("email")

      user = create(:user, email_address: "real@example.com", password: "Password123!", password_set_at: 1.year.ago)
      expect(app_post(app_sign_in_add_email_path, email: "real@example.com")["step"]).to eq("code")
      expect(app_post(app_sign_in_code_path, code: sent_code)["status"]).to eq("signed_in")
      expect(user.user_identities.sole.private_email).to be(true)
    end

    it "trades a browser tab's one-time code for the sign-in, only with the secret behind its challenge" do
      user = create(:user, email_address: "maya@example.com")
      user.user_identities.create!(provider: "google", uid: "a-1", email: "maya@example.com")
      secret = SecureRandom.urlsafe_base64(32)
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(secret), padding: false)

      get app_sign_in_provider_start_path("google", challenge: challenge)
      expect(response.location).to start_with("https://accounts.google.com/")
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      get google_sign_in_callback_path(code: "c", state: state)
      expect(response.location).to start_with("cocoscout://auth?code=")
      handoff = Rack::Utils.parse_query(URI(response.location).query)["code"]

      expect(app_post(app_sign_in_exchange_path, code: handoff, secret: "wrong")["status"]).to eq("error")
      # One try: a wrong secret spends the code.
      expect(app_post(app_sign_in_exchange_path, code: handoff, secret: secret)["status"]).to eq("error")

      get app_sign_in_provider_start_path("google", challenge: challenge)
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      get google_sign_in_callback_path(code: "c", state: state)
      handoff = Rack::Utils.parse_query(URI(response.location).query)["code"]
      expect(app_post(app_sign_in_exchange_path, code: handoff, secret: secret)["status"]).to eq("signed_in")
    end

    it "sends a canceled browser tab back to the app" do
      get app_sign_in_provider_start_path("google", challenge: "c" * 43)
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      get google_sign_in_callback_path(error: "access_denied", state: state)
      expect(response.location).to eq("cocoscout://auth?error=canceled")
    end
  end
end
