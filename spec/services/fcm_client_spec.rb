# frozen_string_literal: true

require "rails_helper"

# Google's push service for the Android app.
RSpec.describe FcmClient do
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:service_account) do
    { "type" => "service_account", "project_id" => "cocoscout-test", "private_key_id" => "abc",
      "private_key" => key.to_pem, "client_email" => "push@cocoscout-test.iam.gserviceaccount.com",
      "token_uri" => "https://oauth2.googleapis.com/token" }
  end

  def with_env(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("FCM_SERVICE_ACCOUNT_JSON").and_return(value)
    allow(ENV).to receive(:fetch).with("FCM_SERVICE_ACCOUNT_JSON").and_return(value)
  end

  it "reads the key file as is, or base64'd onto one line as .kamal/secrets sends it" do
    with_env(JSON.pretty_generate(service_account))
    expect(described_class.service_account).to eq(service_account)

    with_env(Base64.strict_encode64(JSON.pretty_generate(service_account)))
    expect(described_class.service_account).to eq(service_account)
    expect(described_class).to be_configured
  end

  it "sends data-only, high-priority messages to the project, and reads Google's error codes" do
    with_env(service_account.to_json)
    allow(described_class).to receive(:access_token).and_return("ya29.test")
    http = instance_double(Net::HTTP, started?: true, finish: nil)
    allow(Net::HTTP).to receive(:start).with("fcm.googleapis.com", 443, hash_including(use_ssl: true)).and_return(http)
    gone = { error: { code: 404, status: "NOT_FOUND",
                      details: [ { "@type" => "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: "UNREGISTERED" } ] } }
    requests = []
    allow(http).to receive(:request) do |request|
      requests << request
      requests.one? ? instance_double(Net::HTTPResponse, code: "200", body: "{}") : instance_double(Net::HTTPResponse, code: "404", body: gone.to_json)
    end

    results = described_class.open do |fcm|
      [ fcm.deliver("token-1", { "path" => "/my/messages/5", "badge" => 2 }), fcm.deliver("token-2", {}) ]
    end

    expect(requests.first.path).to eq("/v1/projects/cocoscout-test/messages:send")
    expect(requests.first["Authorization"]).to eq("Bearer ya29.test")
    expect(JSON.parse(requests.first.body)).to eq(
      "message" => { "token" => "token-1", "data" => { "path" => "/my/messages/5", "badge" => "2" }, "android" => { "priority" => "HIGH" } }
    )
    expect(results.first).to be_ok
    expect(results.last).to have_attributes(status: 404, reason: "UNREGISTERED")
    expect(results.last).to be_gone
    expect(FcmClient::Result.new(status: 400, reason: "INVALID_ARGUMENT")).not_to be_gone
  end
end
