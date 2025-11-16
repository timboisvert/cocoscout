require 'rails_helper'

RSpec.describe QuestionTypes::MultipleMultipleType do
  describe '.key' do
    it 'returns the correct key' do
      expect(QuestionTypes::MultipleMultipleType.key).to eq('multiple-multiple')
    end
  end

  describe '.label' do
    it 'returns the correct label' do
      expect(QuestionTypes::MultipleMultipleType.label).to eq('Select Multiple Options')
    end
  end

  describe '.needs_options?' do
    it 'returns true' do
      expect(QuestionTypes::MultipleMultipleType.needs_options?).to be true
    end
  end

  describe '.parse_answer_value' do
    it 'parses JSON hash and returns keys' do
      value = '{"Option 1"=>"Option 1", "Option 2"=>"Option 2"}'
      result = QuestionTypes::MultipleMultipleType.parse_answer_value(value)
      expect(result).to match_array(['Option 1', 'Option 2'])
    end

    it 'handles Ruby hash syntax' do
      value = '{"Option A":"Option A", "Option B":"Option B"}'
      result = QuestionTypes::MultipleMultipleType.parse_answer_value(value)
      expect(result).to match_array(['Option A', 'Option B'])
    end

    it 'returns empty array for invalid JSON' do
      value = 'invalid json'
      result = QuestionTypes::MultipleMultipleType.parse_answer_value(value)
      expect(result).to eq([])
    end

    it 'returns empty array for parsing errors' do
      value = '{'
      result = QuestionTypes::MultipleMultipleType.parse_answer_value(value)
      expect(result).to eq([])
    end
  end

  describe 'registration' do
    it 'is registered in the base registry' do
      expect(QuestionTypes::Base.find('multiple-multiple')).to eq(QuestionTypes::MultipleMultipleType)
    end
  end
end
