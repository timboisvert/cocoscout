# frozen_string_literal: true

require "rails_helper"

RSpec.describe Poster, type: :model do
  let(:production) { create(:production) }

  describe "associations" do
    it { is_expected.to belong_to(:production) }
  end

  describe "validations" do
    it "allows blank name" do
      poster = build(:poster, production: production, name: "")
      # Skip image validation for this test
      allow(poster).to receive(:image_content_type)
      expect(poster).to be_valid
    end

    it "validates name length" do
      poster = build(:poster, production: production, name: "a" * 256)
      allow(poster).to receive(:image_content_type)
      expect(poster).not_to be_valid
      expect(poster.errors[:name]).to be_present
    end
  end

  describe "primary poster behavior" do
    it "sets first poster as primary automatically" do
      poster = Poster.create!(production: production)
      expect(poster.is_primary).to be true
    end

    it "unsets other primaries when new primary is set" do
      poster1 = Poster.create!(production: production)
      poster2 = Poster.create!(production: production)

      poster2.update!(is_primary: true)
      poster1.reload

      expect(poster1.is_primary).to be false
      expect(poster2.is_primary).to be true
    end
  end

  describe ".primary" do
    it "returns only primary posters" do
      poster1 = Poster.create!(production: production)
      Poster.create!(production: production)

      expect(Poster.primary).to contain_exactly(poster1)
    end
  end

  describe "#safe_image_variant" do
    let(:poster) { Poster.create!(production: production) }

    it "returns nil when no image attached" do
      expect(poster.safe_image_variant(:small)).to be_nil
    end
  end
end

FactoryBot.define do
  factory :poster do
    association :production
  end
end unless FactoryBot.factories.registered?(:poster)
