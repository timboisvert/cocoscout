# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfileSkillsService do
  describe ".all_categories" do
    it "returns an array of category names" do
      categories = described_class.all_categories
      expect(categories).to be_an(Array)
      expect(categories).to all(be_a(String))
    end

    it "returns sorted categories" do
      categories = described_class.all_categories
      expect(categories).to eq(categories.sort)
    end
  end

  describe ".skills_for_category" do
    it "returns skills for a valid category" do
      categories = described_class.all_categories
      skip "No categories configured" if categories.empty?

      skills = described_class.skills_for_category(categories.first)
      expect(skills).to be_an(Array)
    end

    it "returns empty array for invalid category" do
      skills = described_class.skills_for_category("nonexistent_category")
      expect(skills).to eq([])
    end
  end

  describe ".all_skills" do
    it "returns a sorted array of all skills" do
      skills = described_class.all_skills
      expect(skills).to be_an(Array)
      expect(skills).to eq(skills.sort)
    end
  end

  describe ".valid_skill?" do
    it "returns true for valid skill in category" do
      categories = described_class.all_categories
      skip "No categories configured" if categories.empty?

      category = categories.first
      skills = described_class.skills_for_category(category)
      skip "No skills in category" if skills.empty?

      expect(described_class.valid_skill?(category, skills.first)).to be true
    end

    it "returns false for invalid skill" do
      categories = described_class.all_categories
      skip "No categories configured" if categories.empty?

      expect(described_class.valid_skill?(categories.first, "fake_skill_xyz")).to be false
    end
  end

  describe ".suggested_sections" do
    it "returns an array of section names" do
      sections = described_class.suggested_sections
      expect(sections).to be_an(Array)
      expect(sections).to include("Theatre", "Film", "Television")
    end
  end

  describe ".category_display_name" do
    it "titleizes and formats category name" do
      expect(described_class.category_display_name("voice_acting")).to eq("Voice Acting")
      expect(described_class.category_display_name("dance")).to eq("Dance")
    end
  end
end
