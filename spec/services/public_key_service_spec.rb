# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicKeyService do
  describe ".generate" do
    it "generates a valid key from a name" do
      key = described_class.generate("John Smith")
      expect(key).to match(/\A[a-z0-9][a-z0-9-]{2,29}\z/)
    end

    it "handles special characters in name" do
      key = described_class.generate("José García-López")
      expect(key).to match(/\A[a-z0-9][a-z0-9-]{2,29}\z/)
    end

    it "truncates long names" do
      key = described_class.generate("A" * 100)
      expect(key.length).to be <= 30
    end

    it "adds suffix for duplicate keys" do
      person = create(:person, name: "Test Person")
      # Generate a key that would conflict
      new_key = described_class.generate(person.name)
      expect(new_key).not_to eq(person.public_key)
    end
  end

  describe ".validate" do
    it "returns available true for valid unique key" do
      result = described_class.validate("unique-test-key")
      expect(result[:available]).to be true
    end

    it "returns available false for too short key" do
      result = described_class.validate("ab")
      expect(result[:available]).to be false
      expect(result[:message]).to include("3-30 characters")
    end

    it "returns available false for invalid characters" do
      result = described_class.validate("Test Key!")
      expect(result[:available]).to be false
    end

    it "returns available false for key starting with hyphen" do
      result = described_class.validate("-test-key")
      expect(result[:available]).to be false
    end

    it "returns available false for taken key" do
      person = create(:person)
      result = described_class.validate(person.public_key)
      expect(result[:available]).to be false
      expect(result[:message]).to include("taken")
    end

    context "with exclude_entity" do
      it "allows current entity's own key" do
        person = create(:person)
        result = described_class.validate(person.public_key, exclude_entity: person)
        expect(result[:available]).to be false
        expect(result[:message]).to include("already your current")
      end
    end
  end
end
