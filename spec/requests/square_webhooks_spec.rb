# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Square webhooks", type: :request do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:integration) { org.integrations.create!(provider: "square", tokens: { "access_token" => "tok", "merchant_id" => "M1" }) }
  let(:key) { "sig-key" }

  before { allow(SquareApi).to receive(:webhook_signature_key).and_return(key) }

  def signed(body)
    url = square_webhook_url
    Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", key, url + body))
  end

  it "re-pulls the merchant's day when the signature checks out, once per event" do
    body = { event_id: "evt-1", type: "payment.updated", merchant_id: "M1" }.to_json
    expect {
      post square_webhook_path, params: body, headers: { "CONTENT_TYPE" => "application/json", "x-square-hmacsha256-signature" => signed(body) }
    }.to have_enqueued_job(SquarePullJob).with(integration.id, hash_including(trigger: "webhook"))
    expect(response).to have_http_status(:ok)
    expect {
      post square_webhook_path, params: body, headers: { "CONTENT_TYPE" => "application/json", "x-square-hmacsha256-signature" => signed(body) }
    }.not_to have_enqueued_job(SquarePullJob)
  end

  it "rejects a body that was not signed by Square" do
    body = { event_id: "evt-2", type: "payment.updated", merchant_id: "M1" }.to_json
    post square_webhook_path, params: body, headers: { "CONTENT_TYPE" => "application/json", "x-square-hmacsha256-signature" => "bad" }
    expect(response).to have_http_status(:unauthorized)
  end
end
