# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInCode do
  let(:email) { "maya@example.com" }

  describe ".issue!" do
    it "makes a 6-digit code and keeps only its digest" do
      record, code = described_class.issue!(email: " Maya@Example.com ", purpose: "sign_in")

      expect(code).to match(/\A\d{6}\z/)
      expect(record.email).to eq(email)
      expect(record.code_digest).not_to include(code)
      expect(record.expires_at).to be_within(5.seconds).of(described_class::LIFETIME.from_now)
    end

    it "ends the earlier code for the same address and purpose" do
      described_class.issue!(email: email, purpose: "sign_in")
      described_class.issue!(email: email, purpose: "sign_in")
      described_class.issue!(email: email, purpose: "confirm_address")

      expect(described_class.for_address(email).live.where(purpose: "sign_in").count).to eq(1)
      expect(described_class.for_address(email).live.count).to eq(2)
    end
  end

  describe ".redeem" do
    it "accepts the right code once, and spaces or dashes in it" do
      _record, code = described_class.issue!(email: email, purpose: "sign_in")

      status, record = described_class.redeem(email: email, purpose: "sign_in", code: "#{code[0, 3]} #{code[3, 3]}")
      expect(status).to eq(:ok)
      expect(record.used_at).to be_present
      expect(described_class.redeem(email: email, purpose: "sign_in", code: code).first).to eq(:expired)
    end

    it "does not accept a code made for another purpose" do
      _record, code = described_class.issue!(email: email, purpose: "confirm_address")

      expect(described_class.redeem(email: email, purpose: "sign_in", code: code).first).to eq(:expired)
    end

    it "locks after five wrong tries, even for the right code" do
      _record, code = described_class.issue!(email: email, purpose: "sign_in")
      wrong = code == "000000" ? "111111" : "000000"

      4.times { expect(described_class.redeem(email: email, purpose: "sign_in", code: wrong).first).to eq(:wrong) }
      expect(described_class.redeem(email: email, purpose: "sign_in", code: wrong).first).to eq(:locked)
      expect(described_class.redeem(email: email, purpose: "sign_in", code: code).first).to eq(:locked)
    end

    it "says expired once the lifetime has passed" do
      _record, code = described_class.issue!(email: email, purpose: "sign_in")

      travel_to((described_class::LIFETIME + 1.minute).from_now) do
        expect(described_class.redeem(email: email, purpose: "sign_in", code: code).first).to eq(:expired)
      end
    end
  end

  describe ".send_refusal" do
    it "refuses a second code for the same purpose within the resend wait, then allows it" do
      described_class.issue!(email: email, purpose: "sign_in")
      expect(described_class.send_refusal(email, "sign_in")).to eq(:too_soon)

      travel_to(1.minute.from_now) { expect(described_class.send_refusal(email, "sign_in")).to be_nil }
    end

    # "Use the code we just sent" would be untrue: that code is for something else.
    it "does not hold back a code for a different purpose" do
      described_class.issue!(email: email, purpose: "sign_in")
      expect(described_class.send_refusal(email, "change_password")).to be_nil
    end

    it "refuses once the address has had its share for the hour, whatever the codes were for" do
      described_class::SENDS_PER_HOUR.times do |i|
        travel_to((i * 2).minutes.from_now) { described_class.issue!(email: email, purpose: i.even? ? "sign_in" : "change_password") }
      end

      travel_to(15.minutes.from_now) { expect(described_class.send_refusal(email, "sign_in")).to eq(:too_many) }
      travel_to(2.hours.from_now) { expect(described_class.send_refusal(email, "sign_in")).to be_nil }
    end
  end
end
