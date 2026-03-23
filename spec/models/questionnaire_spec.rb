# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Questionnaire, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      questionnaire = build(:questionnaire)
      expect(questionnaire).to be_valid
    end

    it 'is invalid without title' do
      questionnaire = build(:questionnaire, title: nil)
      expect(questionnaire).not_to be_valid
      expect(questionnaire.errors[:title]).to include("can't be blank")
    end

    it 'requires token to be unique' do
      create(:questionnaire, token: 'UNIQUE')
      questionnaire2 = build(:questionnaire, token: 'UNIQUE')
      expect(questionnaire2).not_to be_valid
      expect(questionnaire2.errors[:token]).to be_present
    end
  end

  describe 'associations' do
    it 'belongs to organization' do
      questionnaire = create(:questionnaire)
      expect(questionnaire.organization).to be_present
      expect(questionnaire).to respond_to(:organization)
    end

    it 'optionally belongs to production' do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:production)
    end

    it 'has many questions' do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:questions)
    end

    it 'has many questionnaire_invitations' do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:questionnaire_invitations)
    end

    it 'has many questionnaire_responses' do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:questionnaire_responses)
    end
  end

  describe 'rich text' do
    it 'has rich text instruction_text' do
      questionnaire = create(:questionnaire)
      expect(questionnaire).to respond_to(:instruction_text)
    end
  end

  describe 'token generation' do
    it 'generates a token on create' do
      questionnaire = create(:questionnaire, token: nil)
      expect(questionnaire.token).to be_present
      expect(questionnaire.token.length).to eq(6)
    end

    it 'generates unique tokens' do
      questionnaire1 = create(:questionnaire)
      questionnaire2 = create(:questionnaire)
      expect(questionnaire1.token).not_to eq(questionnaire2.token)
    end
  end

  describe '#respond_url' do
    it 'returns the correct URL' do
      questionnaire = create(:questionnaire, token: 'ABC123')
      expect(questionnaire.respond_url).to include('/my/questionnaires/ABC123/form')
    end
  end
end
