# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuestionTypes::MultipleSingleType do
  describe '.key' do
    it 'returns the correct key' do
      expect(QuestionTypes::MultipleSingleType.key).to eq('multiple-single')
    end
  end

  describe '.label' do
    it 'returns the correct label' do
      expect(QuestionTypes::MultipleSingleType.label).to eq('Select Single Option')
    end
  end

  describe '.needs_options?' do
    it 'returns true' do
      expect(QuestionTypes::MultipleSingleType.needs_options?).to be true
    end
  end

  describe '.parse_answer_value' do
    it 'parses JSON hash and returns keys' do
      value = '{"Selected Option"=>"Selected Option"}'
      result = QuestionTypes::MultipleSingleType.parse_answer_value(value)
      expect(result).to eq([ 'Selected Option' ])
    end

    it 'handles Ruby hash syntax' do
      value = '{"Option":"Option"}'
      result = QuestionTypes::MultipleSingleType.parse_answer_value(value)
      expect(result).to eq([ 'Option' ])
    end

    it 'returns empty array for invalid JSON' do
      value = 'invalid json'
      result = QuestionTypes::MultipleSingleType.parse_answer_value(value)
      expect(result).to eq([])
    end

    it 'returns empty array for parsing errors' do
      value = '{'
      result = QuestionTypes::MultipleSingleType.parse_answer_value(value)
      expect(result).to eq([])
    end
  end

  describe 'registration' do
    it 'is registered in the base registry' do
      expect(QuestionTypes::Base.find('multiple-single')).to eq(QuestionTypes::MultipleSingleType)
    end
  end
end
