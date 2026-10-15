# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushDeliveryJob do
  let(:user) { create(:user) }
  let!(:phone) { create(:device_token, user: user, token: "b" * 64) }
  let!(:test_phone) { create(:device_token, user: user, token: "c" * 64, apns_environment: "sandbox") }
  let(:notification) do
    { "title" => "Andie", "subtitle" => "Spring Revue", "body" => "Call time is 7", "data" => { "path" => "/my/messages/5" }, "badge" => 2 }
  end

  it "sends to each phone on its own Apple server, and forgets phones Apple says are gone" do
    allow(ApnsClient).to receive(:configured?).and_return(true)
    allow_any_instance_of(ApnsClient).to receive(:close)
    sent = []
    allow_any_instance_of(ApnsClient).to receive(:deliver) do |apns, token, payload|
      sent << [ apns.host, token, payload ]
      gone = token == test_phone.token
      ApnsClient::Result.new(status: gone ? 410 : 200, reason: gone ? "Unregistered" : nil)
    end

    described_class.perform_now(user.id, notification)

    expect(sent.map(&:first)).to contain_exactly(ApnsClient::HOSTS["production"], ApnsClient::HOSTS["sandbox"])
    expect(sent.first.last).to eq("path" => "/my/messages/5",
                                  aps: { alert: { title: "Andie", subtitle: "Spring Revue", body: "Call time is 7" }, sound: "default", badge: 2 })
    expect(DeviceToken.exists?(phone.id)).to be(true)
    expect(DeviceToken.exists?(test_phone.id)).to be(false)
  end

  it "sends Android phones the notification as data, and forgets phones Google says are gone" do
    android = create(:device_token, user: user, platform: "android", token: "fcm-token:#{'a' * 140}")
    uninstalled = create(:device_token, user: user, platform: "android", token: "fcm-gone:#{'b' * 140}")
    allow(ApnsClient).to receive(:configured?).and_return(false)
    allow(FcmClient).to receive(:configured?).and_return(true)
    allow_any_instance_of(FcmClient).to receive(:close)
    sent = []
    allow_any_instance_of(FcmClient).to receive(:deliver) do |_fcm, token, data|
      sent << [ token, data ]
      token == uninstalled.token ? FcmClient::Result.new(status: 404, reason: "UNREGISTERED") : FcmClient::Result.new(status: 200, reason: nil)
    end

    described_class.perform_now(user.id, notification)

    expect(sent.map(&:first)).to contain_exactly(android.token, uninstalled.token)
    expect(sent.first.last).to eq("path" => "/my/messages/5", "title" => "Andie", "subtitle" => "Spring Revue",
                                  "body" => "Call time is 7", "badge" => "2")
    expect(DeviceToken.exists?(android.id)).to be(true)
    expect(DeviceToken.exists?(uninstalled.id)).to be(false)
    expect(DeviceToken.exists?(phone.id)).to be(true)
  end

  it "sends nothing until the APNs key is set" do
    allow(ApnsClient).to receive(:configured?).and_return(false)
    expect_any_instance_of(ApnsClient).not_to receive(:deliver)

    described_class.perform_now(user.id, notification)
  end

  it "signs Apple's token with the key, and reuses it" do
    key = OpenSSL::PKey::EC.generate("prime256v1")
    env = { "APNS_KEY_ID" => "KEY123", "APNS_TEAM_ID" => "3Y9EQJP24Y", "APNS_PRIVATE_KEY" => Base64.strict_encode64(key.to_pem) }
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    env.each do |name, value|
      allow(ENV).to receive(:[]).with(name).and_return(value)
      allow(ENV).to receive(:fetch).with(name).and_return(value)
    end
    ApnsClient.instance_variable_set(:@auth_token, nil)

    token = ApnsClient.auth_token
    payload, header = JWT.decode(token, key, true, algorithm: "ES256")
    expect(header).to include("kid" => "KEY123", "alg" => "ES256")
    expect(payload["iss"]).to eq("3Y9EQJP24Y")
    expect(ApnsClient.auth_token).to eq(token)
  ensure
    ApnsClient.instance_variable_set(:@auth_token, nil)
  end
end
