# frozen_string_literal: true

require "rails_helper"

# The genre catalog is config, but its keys become data (productions.genre) —
# so pin the invariants that would otherwise fail at runtime in the middle of
# producer setup.
RSpec.describe ProductionGenres do
  it "has at least the core genres" do
    expect(described_class.keys).to include("sketch", "improv", "standup", "theater", "variety", "other")
  end

  it "gives every genre a label, description, noun, and placeholder" do
    described_class.keys.each do |key|
      expect(described_class.label(key)).to be_present, "#{key} is missing a label"
      expect(described_class.description(key)).to be_present, "#{key} is missing a description"
      expect(described_class.noun(key)).to be_present
      expect(described_class.name_placeholder(key)).to be_present, "#{key} is missing a name_placeholder"
    end
  end

  it "matches the Production genre validation" do
    production = Production.new(name: "X", genre: "sketch")
    production.valid?
    expect(production.errors[:genre]).to be_empty

    production.genre = "polka"
    production.valid?
    expect(production.errors[:genre]).to be_present
  end
end
