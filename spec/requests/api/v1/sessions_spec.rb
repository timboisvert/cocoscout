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

  describe "DELETE /api/v1/sessions" do
    it "cleans up device token on sign out" do
      token = user.generate_token_for(:api)
      device = create(:device_token, user: user, token: "my_device_token")

      delete api_v1_sessions_path,
        params: { device_token: "my_device_token" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
      expect(DeviceToken.find_by(id: device.id)).to be_nil
    end
  end
end
