# frozen_string_literal: true

require "rails_helper"

# The public signup form's bot defenses: the honeypot field and the signed
# form-age token in AuthController#signup_gate_passed?, plus the Rack::Attack
# blocklist/throttle on POST /signup. Added after the 2026-08-18 proxy-pool
# signup wave.
RSpec.describe "Signup bot defense", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "Password123!" }

  def user_count = User.count

  describe "the form" do
    it "carries a fresh signed token and the honeypot field" do
      get signup_path
      expect(response).to have_http_status(:ok)
      token = response.body[/name="signup_token" value="([^"]+)"/, 1]
      expect(SignupFormToken.age(token)).to eq(0)
      expect(response.body).to include('name="website"')
    end
  end

  describe "the honeypot" do
    it "quietly refuses a submission that filled it" do
      expect do
        post handle_signup_path,
             params: signup_params(email_address: "bot@example.com", password: password, website: "http://spam.example")
      end.not_to change { user_count }
      expect(response).to redirect_to(root_path)
      expect(cookies[:session_id]).to be_blank
    end
  end

  describe "the form token" do
    it "lets a submission through once the form has been open a few seconds" do
      expect do
        post handle_signup_path, params: signup_params(email_address: "human@example.com", password: password)
      end.to change { user_count }.by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "refuses a submission posted instantly, but hands back the same token so a real person can just retry" do
      token = SignupFormToken.generate
      expect do
        post handle_signup_path, params: { user: { email_address: "fast@example.com", password: password }, signup_token: token }
      end.not_to change { user_count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Please click Create Account again")
      expect(response.body).to include(%(value="#{token}"))

      travel(SignupFormToken::MIN_AGE + 1.second) do
        expect do
          post handle_signup_path, params: { user: { email_address: "fast@example.com", password: password }, signup_token: token }
        end.to change { user_count }.by(1)
      end
    end

    it "refuses a submission with no token and re-renders with a fresh one" do
      expect do
        post handle_signup_path, params: { user: { email_address: "cold@example.com", password: password } }
      end.not_to change { user_count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/name="signup_token" value="[^"]+"/)
    end

    it "refuses a tampered token" do
      expect do
        post handle_signup_path,
             params: { user: { email_address: "forged@example.com", password: password }, signup_token: "not-a-real-token" }
      end.not_to change { user_count }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses an expired token" do
      expect do
        post handle_signup_path,
             params: signup_params(email_address: "stale@example.com", password: password,
                                   issued_at: SignupFormToken::MAX_AGE.ago - 1.minute)
      end.not_to change { user_count }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "Rack::Attack" do
    around do |example|
      was_enabled = Rack::Attack.enabled
      previous_store = Rack::Attack.cache.store
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rack::Attack.enabled = was_enabled
      Rack::Attack.cache.store = previous_store
    end

    def post_signup(from:, email: "someone@example.com")
      post handle_signup_path,
           params: signup_params(email_address: email, password: password),
           env: { "REMOTE_ADDR" => from }
    end

    it "blocks POST /signup and /signin from the blocked ranges" do
      expect { post_signup(from: "169.58.179.180") }.not_to change { user_count }
      expect(response).to have_http_status(:forbidden)

      post handle_signin_path, params: { email_address: "x@example.com", password: "y" }, env: { "REMOTE_ADDR" => "169.58.0.1" }
      expect(response).to have_http_status(:forbidden)
    end

    it "still serves GET /signup from a blocked range (only the auth posts are refused)" do
      get signup_path, env: { "REMOTE_ADDR" => "169.58.179.180" }
      expect(response).to have_http_status(:ok)
    end

    it "lets an ordinary address sign up" do
      expect { post_signup(from: "172.58.167.89") }.to change { user_count }.by(1)
    end

    it "caps signups per /16 across rotating addresses" do
      10.times do |i|
        post_signup(from: "203.0.#{i}.#{i + 1}", email: "user#{i}@example.com")
        expect(response).to have_http_status(:redirect), "signup #{i} from a fresh address in the /16 should pass"
      end

      expect { post_signup(from: "203.0.99.99", email: "user11@example.com") }.not_to change { user_count }
      expect(response).to have_http_status(:too_many_requests)

      # A different /16 is untouched.
      expect { post_signup(from: "198.51.100.7", email: "elsewhere@example.com") }.to change { user_count }.by(1)
    end
  end
end
