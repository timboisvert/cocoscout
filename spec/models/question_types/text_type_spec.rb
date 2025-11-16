require 'rails_helper'

RSpec.describe QuestionTypes::TextType do
  describe '.key' do
    it 'returns the correct key' do
      expect(QuestionTypes::TextType.key).to eq('text')
    end
  end

  describe '.label' do
    it 'returns the correct label' do
      expect(QuestionTypes::TextType.label).to eq('Short Text')
    end
  end

  describe '.needs_options?' do
    it 'returns false' do
      expect(QuestionTypes::TextType.needs_options?).to be false
    end
  end

  describe '.parse_answer_value' do
    it 'returns value in an array' do
      expect(QuestionTypes::TextType.parse_answer_value('test answer')).to eq(['test answer'])
    end

    it 'handles empty values' do
      expect(QuestionTypes::TextType.parse_answer_value('')).to eq([''])
    end

    it 'handles nil values' do
      expect(QuestionTypes::TextType.parse_answer_value(nil)).to eq([nil])
    end
  end

  describe 'registration' do
    it 'is registered in the base registry' do
      expect(QuestionTypes::Base.find('text')).to eq(QuestionTypes::TextType)
    end
  end
end
