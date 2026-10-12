# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeviceLabel do
  it "names the app, browsers and devices" do
    expect(described_class.from_user_agent("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Turbo Native iOS")).to eq("CocoScout app on iPhone")
    expect(described_class.from_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15")).to eq("Safari on Mac")
    expect(described_class.from_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36 Edg/129.0")).to eq("Edge on Windows")
    expect(described_class.from_user_agent("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0 Mobile/15E148 Safari/604.1")).to eq("Chrome on iPhone")
    expect(described_class.from_user_agent(nil)).to eq("A browser")
  end
end
