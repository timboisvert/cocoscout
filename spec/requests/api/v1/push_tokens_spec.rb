# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Push Tokens", type: :request do
  let(:user) { create(:user) }
  let(:api_token) { user.generate_token_for(:api) }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "POST /api/v1/push_tokens" do
    it "registers a new device token" do
      expect {
        post api_v1_push_tokens_path,
          params: { token: "apns_token_123", platform: "ios" },
          headers: auth_headers
      }.to change(DeviceToken, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["id"]).to be_present
    end

    it "is idempotent for the same token and platform" do
      create(:device_token, user: user, token: "apns_token_123", platform: "ios")

      expect {
        post api_v1_push_tokens_path,
          params: { token: "apns_token_123", platform: "ios" },
          headers: auth_headers
      }.not_to change(DeviceToken, :count)

      expect(response).to have_http_status(:created)
    end

    it "rejects requests without auth" do
      post api_v1_push_tokens_path, params: { token: "abc", platform: "ios" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects invalid platform" do
      post api_v1_push_tokens_path,
        params: { token: "abc", platform: "windows" },
        headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/push_tokens/:id" do
    it "removes a device token by token value" do
      device = create(:device_token, user: user, token: "apns_token_123", platform: "ios")

      expect {
        delete api_v1_push_token_path(device.token), headers: auth_headers
      }.to change(DeviceToken, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "returns not found for unknown token" do
      delete api_v1_push_token_path("nonexistent"), headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end

    it "cannot delete another user's token" do
      other_user = create(:user)
      other_device = create(:device_token, user: other_user, token: "other_token", platform: "ios")

      delete api_v1_push_token_path(other_device.token), headers: auth_headers

      expect(response).to have_http_status(:not_found)
      expect(DeviceToken.find_by(id: other_device.id)).to be_present
    end
  end
end
