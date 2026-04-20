# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeviceToken, type: :model do
  describe "validations" do
    subject { build(:device_token) }

    it { is_expected.to be_valid }

    it "requires a token" do
      subject.token = nil
      expect(subject).not_to be_valid
    end

    it "requires a platform" do
      subject.platform = nil
      expect(subject).not_to be_valid
    end

    it "only allows ios and android platforms" do
      subject.platform = "windows"
      expect(subject).not_to be_valid
    end

    it "enforces uniqueness of token per platform" do
      create(:device_token, token: "abc123", platform: "ios")
      duplicate = build(:device_token, token: "abc123", platform: "ios")
      expect(duplicate).not_to be_valid
    end

    it "allows same token on different platforms" do
      create(:device_token, token: "abc123", platform: "ios")
      android = build(:device_token, token: "abc123", platform: "android")
      expect(android).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a user" do
      device_token = create(:device_token)
      expect(device_token.user).to be_a(User)
    end
  end
end
