# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contractor, "payment methods" do
  let(:contractor) { create(:contractor) }

  describe "#venmo_configured?" do
    it "returns false when venmo_identifier is blank" do
      expect(contractor.venmo_configured?).to be false
    end

    it "returns true when venmo_identifier is present" do
      contractor.update!(venmo_identifier: "danthecontractor")
      expect(contractor.venmo_configured?).to be true
    end
  end

  describe "#zelle_configured?" do
    it "returns false when zelle_identifier is blank" do
      expect(contractor.zelle_configured?).to be false
    end

    it "returns true when zelle_identifier is present" do
      contractor.update!(zelle_identifier: "dan@example.com")
      expect(contractor.zelle_configured?).to be true
    end
  end

  describe "#any_payment_method_configured?" do
    it "returns false when neither is configured" do
      expect(contractor.any_payment_method_configured?).to be false
    end

    it "returns true when venmo is configured" do
      contractor.update!(venmo_identifier: "danthecontractor")
      expect(contractor.any_payment_method_configured?).to be true
    end

    it "returns true when zelle is configured" do
      contractor.update!(zelle_identifier: "dan@example.com")
      expect(contractor.any_payment_method_configured?).to be true
    end
  end

  describe "#formatted_venmo_identifier" do
    it "returns nil when not configured" do
      expect(contractor.formatted_venmo_identifier).to be_nil
    end

    it "formats with @ prefix" do
      contractor.update!(venmo_identifier: "danthecontractor")
      expect(contractor.formatted_venmo_identifier).to eq("@danthecontractor")
    end

    it "strips existing @ prefix" do
      contractor.update!(venmo_identifier: "@danthecontractor")
      expect(contractor.formatted_venmo_identifier).to eq("@danthecontractor")
    end
  end

  describe "#formatted_zelle_identifier" do
    it "returns nil when not configured" do
      expect(contractor.formatted_zelle_identifier).to be_nil
    end

    it "returns the identifier as-is" do
      contractor.update!(zelle_identifier: "dan@example.com")
      expect(contractor.formatted_zelle_identifier).to eq("dan@example.com")
    end
  end

  describe "#venmo_payment_link" do
    it "returns nil when not configured" do
      expect(contractor.venmo_payment_link(100)).to be_nil
    end

    it "generates a venmo deep link when configured" do
      contractor.update!(venmo_identifier: "danthecontractor")
      link = contractor.venmo_payment_link(100, "Test payment")
      expect(link).to start_with("venmo://paycharge?")
      expect(link).to include("recipients=danthecontractor")
      expect(link).to include("amount=100.0")
      expect(link).to include("note=Test+payment")
    end
  end

  describe "#preferred_payment_info" do
    it "returns nil when nothing configured" do
      expect(contractor.preferred_payment_info).to be_nil
    end

    it "prefers venmo when both configured" do
      contractor.update!(venmo_identifier: "dan", zelle_identifier: "dan@example.com")
      info = contractor.preferred_payment_info
      expect(info[:method]).to eq("venmo")
      expect(info[:identifier]).to eq("@dan")
    end

    it "returns zelle when only zelle configured" do
      contractor.update!(zelle_identifier: "dan@example.com")
      info = contractor.preferred_payment_info
      expect(info[:method]).to eq("zelle")
      expect(info[:identifier]).to eq("dan@example.com")
    end
  end

  describe "#initials" do
    it "returns first two initials" do
      contractor.update!(name: "Dan Smith Productions")
      expect(contractor.initials).to eq("DS")
    end

    it "returns single initial for single name" do
      contractor.update!(name: "Dan")
      expect(contractor.initials).to eq("D")
    end
  end

  describe "#venmo_ready_for_payouts?" do
    it "delegates to venmo_configured?" do
      expect(contractor.venmo_ready_for_payouts?).to be false
      contractor.update!(venmo_identifier: "dan")
      expect(contractor.venmo_ready_for_payouts?).to be true
    end
  end

  describe "#zelle_ready_for_payouts?" do
    it "delegates to zelle_configured?" do
      expect(contractor.zelle_ready_for_payouts?).to be false
      contractor.update!(zelle_identifier: "dan@example.com")
      expect(contractor.zelle_ready_for_payouts?).to be true
    end
  end
end
