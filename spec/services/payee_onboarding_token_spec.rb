# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayeeOnboardingToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:person) { create(:person) }

  it "round-trips a payee through generate/resolve" do
    token = described_class.generate(person)
    expect(described_class.resolve(token)).to eq(person)
  end

  it "resolves a contractor too" do
    contractor = create(:organization).contractors.create!(name: "Sound Co")
    token = described_class.generate(contractor)
    expect(described_class.resolve(token)).to eq(contractor)
  end

  it "returns nil for a tampered or garbage token" do
    expect(described_class.resolve("not-a-real-token")).to be_nil
    expect(described_class.resolve(described_class.generate(person) + "x")).to be_nil
  end

  it "returns nil once the token has expired" do
    token = described_class.generate(person)
    travel_to(described_class::EXPIRY.from_now + 1.day) do
      expect(described_class.resolve(token)).to be_nil
    end
  end

  it "refuses to generate for an unsupported payee type" do
    expect { described_class.generate(create(:organization)) }.to raise_error(ArgumentError)
  end
end
