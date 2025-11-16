require 'rails_helper'

RSpec.describe QuestionTypes::TextareaType do
  describe '.key' do
    it 'returns the correct key' do
      expect(QuestionTypes::TextareaType.key).to eq('textarea')
    end
  end

  describe '.label' do
    it 'returns the correct label' do
      expect(QuestionTypes::TextareaType.label).to eq('Long Text')
    end
  end

  describe '.needs_options?' do
    it 'returns false' do
      expect(QuestionTypes::TextareaType.needs_options?).to be false
    end
  end

  describe '.parse_answer_value' do
    it 'returns value in an array' do
      long_text = "This is a long answer\nwith multiple lines"
      expect(QuestionTypes::TextareaType.parse_answer_value(long_text)).to eq([ long_text ])
    end

    it 'handles empty values' do
      expect(QuestionTypes::TextareaType.parse_answer_value('')).to eq([ '' ])
    end
  end

  describe 'registration' do
    it 'is registered in the base registry' do
      expect(QuestionTypes::Base.find('textarea')).to eq(QuestionTypes::TextareaType)
    end
  end
end
