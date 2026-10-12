# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Sessions", type: :request do
  let(:user) { create(:user, password: "Password123!") }

  describe "POST /api/v1/sessions" do
    it "returns a token with valid credentials" do
      post api_v1_sessions_path, params: { email: user.email_address, password: "Password123!" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["token"]).to be_present
      expect(json["user_id"]).to eq(user.id)
    end

    it "returns unauthorized with invalid credentials" do
      post api_v1_sessions_path, params: { email: user.email_address, password: "wrong" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns unauthorized with non-existent email" do
      post api_v1_sessions_path, params: { email: "nobody@example.com", password: "Password123!" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns a token that can authenticate subsequent requests" do
      post api_v1_sessions_path, params: { email: user.email_address, password: "Password123!" }
      token = JSON.parse(response.body)["token"]

      # Use the token to access a protected endpoint
      post api_v1_push_tokens_path,
        params: { token: "device_abc", platform: "ios" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:created)
    end
  end

  # App sign-ins are device sessions that can be ended (Tim, 2026-10-12).
  describe "ending a phone's session" do
    def sign_in(device_name: nil)
      post api_v1_sessions_path, params: { email: user.email_address, password: "Password123!", device_name: device_name },
                                 headers: { "User-Agent" => "CocoScout/1.0 (iPhone; iOS 26.0) Hotwire Native" }
      JSON.parse(response.body)["token"]
    end

    def authorized?(token)
      post api_v1_push_tokens_path, params: { token: "device_#{SecureRandom.hex(4)}", platform: "ios" },
                                    headers: { "Authorization" => "Bearer #{token}" }
      response.status == 201
    end

    it "keeps only a digest of the token, and names the phone" do
      token = sign_in
      session = user.app_sessions.sole
      expect(session.token_digest).not_to include(token)
      expect(session.label).to eq("iPhone")
      expect(sign_in(device_name: "Tim's iPhone") && user.app_sessions.order(:id).last.label).to eq("Tim's iPhone")
    end

    it "stops a token working the moment the app signs out, taking its push token along" do
      token = sign_in
      expect(authorized?(token)).to be(true)

      delete api_v1_sessions_path, headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
      expect(user.app_sessions).to be_empty
      expect(user.device_tokens).to be_empty
      expect(authorized?(token)).to be(false)
    end

    it "signs every phone out when the password changes" do
      first = sign_in
      second = sign_in
      user.update!(password: "NewPassword456!")

      expect(authorized?(first)).to be(false)
      expect(authorized?(second)).to be(false)
    end

    it "stops a token nobody has used for 30 days" do
      token = sign_in
      user.app_sessions.update_all(last_used_at: 31.days.ago)
      expect(authorized?(token)).to be(false)
    end

    it "answers an unknown email the same way as a wrong password, through authenticate_by" do
      allow(User).to receive(:authenticate_by).and_call_original
      post api_v1_sessions_path, params: { email: "nobody@example.com", password: "Password123!" }
      expect(response).to have_http_status(:unauthorized)
      expect(User).to have_received(:authenticate_by).with(email_address: "nobody@example.com", password: "Password123!")
    end
  end

  describe "DELETE /api/v1/sessions" do
    it "cleans up device token on sign out" do
      token = AppSession.start!(user).last
      device = create(:device_token, user: user, token: "my_device_token")

      delete api_v1_sessions_path,
        params: { device_token: "my_device_token" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
      expect(DeviceToken.find_by(id: device.id)).to be_nil
    end
  end
end
