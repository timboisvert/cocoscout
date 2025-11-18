require 'rails_helper'

RSpec.describe Questionnaire, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      questionnaire = build(:questionnaire)
      expect(questionnaire).to be_valid
    end

    it "is invalid without title" do
      questionnaire = build(:questionnaire, title: nil)
      expect(questionnaire).not_to be_valid
      expect(questionnaire.errors[:title]).to include("can't be blank")
    end

    it "requires token to be unique" do
      questionnaire1 = create(:questionnaire, token: "UNIQUE")
      questionnaire2 = build(:questionnaire, token: "UNIQUE")
      expect(questionnaire2).not_to be_valid
      expect(questionnaire2.errors[:token]).to be_present
    end
  end

  describe "associations" do
    it "belongs to production" do
      questionnaire = create(:questionnaire)
      expect(questionnaire.production).to be_present
      expect(questionnaire).to respond_to(:production)
    end

    it "has many questions" do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:questions)
    end

    it "has many questionnaire_invitations" do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:questionnaire_invitations)
    end

    it "has many questionnaire_responses" do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:questionnaire_responses)
    end
  end

  describe "rich text" do
    it "has rich text header_text" do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:header_text)
    end
  end

  describe "availability fields" do
    it "has include_availability_section field" do
      questionnaire = create(:questionnaire, include_availability_section: true)
      expect(questionnaire.include_availability_section).to be true
    end

    it "defaults include_availability_section to false" do
      questionnaire = create(:questionnaire)
      expect(questionnaire.include_availability_section).to be false
    end

    it "has require_all_availability field" do
      questionnaire = create(:questionnaire, require_all_availability: true)
      expect(questionnaire.require_all_availability).to be true
    end

    it "defaults require_all_availability to false" do
      questionnaire = create(:questionnaire)
      expect(questionnaire.require_all_availability).to be false
    end

    it "serializes availability_event_types as array" do
      questionnaire = create(:questionnaire, availability_event_types: [ "show", "rehearsal" ])
      expect(questionnaire.availability_event_types).to eq([ "show", "rehearsal" ])
      expect(questionnaire.availability_event_types).to be_a(Array)
    end

    it "defaults availability_event_types to empty array" do
      questionnaire = create(:questionnaire)
      expect(questionnaire.availability_event_types).to eq([])
    end

    it "persists availability_event_types correctly" do
      questionnaire = create(:questionnaire, availability_event_types: [ "show", "meeting" ])
      questionnaire.reload
      expect(questionnaire.availability_event_types).to eq([ "show", "meeting" ])
    end
  end

  describe "token generation" do
    it "generates a token on create" do
      questionnaire = create(:questionnaire, token: nil)
      expect(questionnaire.token).to be_present
      expect(questionnaire.token.length).to eq(6)
    end

    it "generates unique tokens" do
      questionnaire1 = create(:questionnaire)
      questionnaire2 = create(:questionnaire)
      expect(questionnaire1.token).not_to eq(questionnaire2.token)
    end
  end

  describe "#respond_url" do
    it "returns the correct URL" do
      questionnaire = create(:questionnaire, token: "ABC123")
      expect(questionnaire.respond_url).to include("/q/ABC123")
    end
  end
end
