# frozen_string_literal: true

require "rails_helper"

RSpec.describe NativeAppVersion do
  let(:v1_ios) { "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu]" }
  let(:v1_1_ios) { "CocoScout/1.1 (12; nav 2) #{v1_ios}" }
  let(:tap_to_pay_android) { "Mozilla/5.0 (Linux; Android 14) Hotwire Native Android; Turbo Native Android; bridge-components: [form menu tap-to-pay]" }
  let(:browser) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15" }

  it "reads a V1 install as generation 1, whatever its version" do
    expect(described_class.nav(v1_ios)).to eq(1)
    expect(described_class.nav(tap_to_pay_android)).to eq(1)
    expect(described_class.production_mode?(v1_ios)).to be(false)
  end

  it "reads a V1.1 build's marker" do
    expect(described_class.nav(v1_1_ios)).to eq(2)
    expect(described_class.version(v1_1_ios)).to eq("1.1")
    expect(described_class.production_mode?(v1_1_ios)).to be(true)
  end

  it "leaves browsers outside the app, with production mode" do
    expect(described_class.nav(browser)).to be_nil
    expect(described_class.production_mode?(browser)).to be(true)
  end

  it "keeps V1's page rules sending Manage to the browser, and generation 2's keeping it in the app" do
    v1 = JSON.parse(Rails.public_path.join("hotwire-native/path-configuration.json").read)
    v2 = JSON.parse(Rails.public_path.join("hotwire-native/nav-2/path-configuration.json").read)
    safari = ->(config) { config["rules"].select { |r| r.dig("properties", "open_in") == "safari" }.flat_map { |r| r["patterns"] } }
    expect(safari.(v1)).to include("^/manage")
    expect(safari.(v2)).not_to include("^/manage")
    expect(safari.(v2)).to include("^/superadmin")
  end
end
